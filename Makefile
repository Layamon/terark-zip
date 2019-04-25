export SHELL=bash
DBG_FLAGS ?= -g3 -D_DEBUG
RLS_FLAGS ?= -O3 -DNDEBUG -g3
WITH_BMI2 ?= $(shell bash ./cpu_has_bmi2.sh)
CMAKE_INSTALL_PREFIX ?= /usr

ifeq "$(origin LD)" "default"
  LD := ${CXX}
endif
ifeq "$(origin CC)" "default"
  CC := ${CXX}
endif

# Makefile is stupid to parsing $(shell echo ')')
tmpfile := $(shell mktemp compiler-XXXXXX)
COMPILER := $(shell ${CXX} tools/configure/compiler.cpp -o ${tmpfile}.exe && ./${tmpfile}.exe && rm -f ${tmpfile}*)
#$(warning COMPILER=${COMPILER})
UNAME_MachineSystem := $(shell uname -m -s | sed 's:[ /]:-:g')
BUILD_NAME := ${UNAME_MachineSystem}-${COMPILER}-bmi2-${WITH_BMI2}
BUILD_ROOT := build/${BUILD_NAME}
ddir:=${BUILD_ROOT}/dbg
rdir:=${BUILD_ROOT}/rls

TERARK_ROOT:=${PWD}
COMMON_C_FLAGS  += -Wformat=2 -Wcomment
COMMON_C_FLAGS  += -Wall -Wextra
COMMON_C_FLAGS  += -Wno-unused-parameter

gen_sh := $(dir $(lastword ${MAKEFILE_LIST}))gen_env_conf.sh

err := $(shell env BOOST_INC=${BOOST_INC} bash ${gen_sh} "${CXX}" ${COMPILER} ${BUILD_ROOT}/env.mk; echo $$?)
ifneq "${err}" "0"
   $(error err = ${err} MAKEFILE_LIST = ${MAKEFILE_LIST}, PWD = ${PWD}, gen_sh = ${gen_sh} "${CXX}" ${COMPILER} ${BUILD_ROOT}/env.mk)
endif

TERARK_INC := -Isrc -I3rdparty/zstd ${BOOST_INC}

include ${BUILD_ROOT}/env.mk

UNAME_System := $(shell uname | sed 's/^\([0-9a-zA-Z]*\).*/\1/')
ifeq (CYGWIN, ${UNAME_System})
  FPIC =
  # lazy expansion
  CYGWIN_LDFLAGS = -Wl,--out-implib=$@ \
				   -Wl,--export-all-symbols \
				   -Wl,--enable-auto-import
  DLL_SUFFIX = .dll.a
  CYG_DLL_FILE = $(shell echo $@ | sed 's:\(.*\)/lib\([^/]*\)\.a$$:\1/cyg\2:')
  COMMON_C_FLAGS += -D_GNU_SOURCE
else
  ifeq (Darwin,${UNAME_System})
    DLL_SUFFIX = .dylib
  else
    DLL_SUFFIX = .so
  endif
  FPIC = -fPIC
  CYG_DLL_FILE = $@
endif
override CFLAGS += ${FPIC}
override CXXFLAGS += ${FPIC}
override LDFLAGS += ${FPIC}

ifeq "$(shell a=${COMPILER};echo $${a:0:3})" "g++"
  ifeq (Linux, ${UNAME_System})
    override LDFLAGS += -rdynamic
  endif
  ifeq (${UNAME_System},Darwin)
    COMMON_C_FLAGS += -Wa,-q
  endif
  override CXXFLAGS += -time
  ifeq "$(shell echo ${COMPILER} | awk -F- '{if ($$2 >= 4.8) print 1;}')" "1"
    CXX_STD := -std=gnu++1y
  endif
  ifeq "$(shell echo ${COMPILER} | awk -F- '{if ($$2 >= 9.0) print 1;}')" "1"
    COMMON_C_FLAGS += -Wno-alloc-size-larger-than
  endif
endif

ifeq "${CXX_STD}" ""
  CXX_STD := -std=gnu++11
endif

# icc or icpc
ifeq "$(shell a=${COMPILER};echo $${a:0:2})" "ic"
  override CXXFLAGS += -xHost -fasm-blocks
  CPU = -xHost
else
  CPU = -march=native
  COMMON_C_FLAGS  += -Wno-deprecated-declarations
  ifeq "$(shell a=${COMPILER};echo $${a:0:5})" "clang"
    COMMON_C_FLAGS  += -fstrict-aliasing
  else
    COMMON_C_FLAGS  += -Wstrict-aliasing=3
  endif
endif

ifeq (${WITH_BMI2},1)
  CPU += -mbmi -mbmi2
else
  CPU += -mno-bmi -mno-bmi2
endif

ifneq (${WITH_TBB},)
  COMMON_C_FLAGS += -DTERARK_WITH_TBB=${WITH_TBB}
  override LIBS += -ltbb
endif

ifeq "$(shell a=${COMPILER};echo $${a:0:5})" "clang"
  COMMON_C_FLAGS += -fcolor-diagnostics
endif

#CXXFLAGS +=
#CXXFLAGS += -fpermissive
#CXXFLAGS += -fexceptions
#CXXFLAGS += -fdump-translation-unit -fdump-class-hierarchy

override CFLAGS += ${COMMON_C_FLAGS}
override CXXFLAGS += ${COMMON_C_FLAGS}
#$(error ${CXXFLAGS} "----" ${COMMON_C_FLAGS})

DEFS := -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE
DEFS += -DDIVSUFSORT_API=
override CFLAGS   += ${DEFS}
override CXXFLAGS += ${DEFS}

override INCS := ${TERARK_INC} ${INCS}

LIBBOOST ?=
#LIBBOOST += -lboost_thread${BOOST_SUFFIX}
#LIBBOOST += -lboost_date_time${BOOST_SUFFIX}
#LIBBOOST += -lboost_system${BOOST_SUFFIX}

#LIBS += -ldl
#LIBS += -lpthread
#LIBS += ${LIBBOOST}

#extf = -pie
extf = -fno-stack-protector
#extf+=-fno-stack-protector-all
override CFLAGS += ${extf}
#override CFLAGS += -g3
override CXXFLAGS += ${extf}
#override CXXFLAGS += -g3
#CXXFLAGS += -fnothrow-opt

ifeq (, ${prefix})
  ifeq (root, ${USER})
    prefix := /usr
  else
    prefix := /home/${USER}
  endif
endif

#$(warning prefix=${prefix} LIBS=${LIBS})

#obsoleted_src =  \
#	$(wildcard src/obsoleted/terark/thread/*.cpp) \
#	$(wildcard src/obsoleted/terark/thread/posix/*.cpp) \
#	$(wildcard src/obsoleted/wordseg/*.cpp)
#LIBS += -liconv

ifneq "$(shell a=${COMPILER};echo $${a:0:5})" "clang"
  override LIBS += -lgomp
endif

c_src := \
   $(wildcard src/terark/c/*.c) \
   $(wildcard src/terark/c/*.cpp)

zip_src := \
    src/terark/io/BzipStream.cpp \
	src/terark/io/GzipStream.cpp

rpc_src := \
   $(wildcard src/terark/inet/*.cpp) \
   $(wildcard src/terark/rpc/*.cpp)

core_src := \
   $(wildcard src/terark/*.cpp) \
   $(wildcard src/terark/io/*.cpp) \
   $(wildcard src/terark/util/*.cpp) \
   $(wildcard src/terark/thread/*.cpp) \
   $(wildcard src/terark/succinct/*.cpp) \
   ${obsoleted_src}

core_src := $(filter-out ${zip_src}, ${core_src})
core_src += ${BUILD_ROOT}/git-version-core.cpp


fsa_src := $(wildcard src/terark/fsa/*.cpp)
fsa_src += $(wildcard src/terark/zsrch/*.cpp)
fsa_src += ${BUILD_ROOT}/git-version-fsa.cpp

zbs_src := $(wildcard src/terark/entropy/*.cpp)
zbs_src += $(wildcard src/terark/zbs/*.cpp)
zbs_src += ${BUILD_ROOT}/git-version-zbs.cpp

zstd_src := $(wildcard 3rdparty/zstd/zstd/common/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/compress/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/decompress/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/deprecated/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/dictBuilder/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/legacy/*.c)

zbs_src += ${zstd_src}

#function definition
#@param:${1} -- targets var prefix, such as bdb_util | core
#@param:${2} -- build type: d | r
objs = $(addprefix ${${2}dir}/, $(addsuffix .o, $(basename ${${1}_src})))

zstd_d_o := $(call objs,zstd,d)
zstd_r_o := $(call objs,zstd,r)

core_d_o := $(call objs,core,d)
core_r_o := $(call objs,core,r)
core_d := ${BUILD_ROOT}/lib/libterark-core-${COMPILER}-d${DLL_SUFFIX}
core_r := ${BUILD_ROOT}/lib/libterark-core-${COMPILER}-r${DLL_SUFFIX}
static_core_d := ${BUILD_ROOT}/lib/libterark-core-${COMPILER}-d.a
static_core_r := ${BUILD_ROOT}/lib/libterark-core-${COMPILER}-r.a

fsa_d_o := $(call objs,fsa,d)
fsa_r_o := $(call objs,fsa,r)
fsa_d := ${BUILD_ROOT}/lib/libterark-fsa-${COMPILER}-d${DLL_SUFFIX}
fsa_r := ${BUILD_ROOT}/lib/libterark-fsa-${COMPILER}-r${DLL_SUFFIX}
static_fsa_d := ${BUILD_ROOT}/lib/libterark-fsa-${COMPILER}-d.a
static_fsa_r := ${BUILD_ROOT}/lib/libterark-fsa-${COMPILER}-r.a

zbs_d_o := $(call objs,zbs,d)
zbs_r_o := $(call objs,zbs,r)
zbs_d := ${BUILD_ROOT}/lib/libterark-zbs-${COMPILER}-d${DLL_SUFFIX}
zbs_r := ${BUILD_ROOT}/lib/libterark-zbs-${COMPILER}-r${DLL_SUFFIX}
static_zbs_d := ${BUILD_ROOT}/lib/libterark-zbs-${COMPILER}-d.a
static_zbs_r := ${BUILD_ROOT}/lib/libterark-zbs-${COMPILER}-r.a

rpc_d_o := $(call objs,rpc,d)
rpc_r_o := $(call objs,rpc,r)
rpc_d := ${BUILD_ROOT}/lib/libterark-rpc-${COMPILER}-d${DLL_SUFFIX}
rpc_r := ${BUILD_ROOT}/lib/libterark-rpc-${COMPILER}-r${DLL_SUFFIX}
static_rpc_d := ${BUILD_ROOT}/lib/libterark-rpc-${COMPILER}-d.a
static_rpc_r := ${BUILD_ROOT}/lib/libterark-rpc-${COMPILER}-r.a

core := ${core_d} ${core_r} ${static_core_d} ${static_core_r}
fsa  := ${fsa_d}  ${fsa_r}  ${static_fsa_d}  ${static_fsa_r}
zbs  := ${zbs_d}  ${zbs_r}  ${static_zbs_d}  ${static_zbs_r}

ALL_TARGETS = ${MAYBE_DBB_DBG} ${MAYBE_DBB_RLS} core fsa rpc zbs
DBG_TARGETS = ${MAYBE_DBB_DBG} ${core_d} ${fsa_d} ${zbs_d} ${rpc_d}
RLS_TARGETS = ${MAYBE_DBB_RLS} ${core_r} ${fsa_r} ${zbs_r} ${rpc_r}

.PHONY : default all core fsa zbs

default : fsa core zbs
all : ${ALL_TARGETS}
core: ${core}
fsa: ${fsa}
zbs: ${zbs}
rpc: ${rpc_d} ${rpc_r} ${static_rpc_d} ${static_rpc_r}

OpenSources := $(shell find -H src 3rdparty -name '*.h' -o -name '*.hpp' -o -name '*.cc' -o -name '*.cpp' -o -name '*.c')
ObfuseFiles := \
	src/terark/fsa/fsa_cache_detail.hpp \
	src/terark/fsa/nest_louds_trie.cpp \
	src/terark/fsa/nest_louds_trie.hpp \
	src/terark/fsa/nest_louds_trie_inline.hpp \
	src/terark/zbs/dict_zip_blob_store.cpp \
	src/terark/zbs/suffix_array_dict.cpp

NotObfuseFiles := $(filter-out ${ObfuseFiles}, ${OpenSources})

allsrc = ${core_src} ${fsa_src} ${zbs_src}
alldep = $(addprefix ${rdir}/, $(addsuffix .dep, $(basename ${allsrc}))) \
         $(addprefix ${ddir}/, $(addsuffix .dep, $(basename ${allsrc})))

.PHONY : dbg rls
dbg: ${DBG_TARGETS}
rls: ${RLS_TARGETS}

.PHONY: obfuscate
obfuscate: $(addprefix ../obfuscated-terark/, ${ObfuseFiles})
	mkdir -p               ../obfuscated-terark/tools
	cp -rf tools/configure ../obfuscated-terark/tools
	cp -rf *.sh ../obfuscated-terark
	@for f in `find 3rdparty -name 'Makefile*'` \
				Makefile ${NotObfuseFiles}; \
	do \
		dir=`dirname ../obfuscated-terark/$$f`; \
		mkdir -p $$dir; \
		echo cp -a $$f $$dir; \
		cp -a $$f $$dir; \
	done

../obfuscated-terark/%: % tools/codegen/fuck_bom_out.exe
	@mkdir -p $(dir $@)
	tools/codegen/fuck_bom_out.exe < $< | perl ./obfuscate.pl > $@

tools/codegen/fuck_bom_out.exe: tools/codegen/fuck_bom_out.cpp
	g++ -o $@ $<

ifneq (${UNAME_System},Darwin)
${core_d} ${core_r} : LIBS += -lrt -lpthread
endif
${core_d} : LIBS := $(filter-out -lterark-core-${COMPILER}-d, ${LIBS})
${core_r} : LIBS := $(filter-out -lterark-core-${COMPILER}-r, ${LIBS})

${fsa_d} : LIBS := $(filter-out -lterark-fsa-${COMPILER}-d, -L${BUILD_ROOT}/lib -lterark-core-${COMPILER}-d ${LIBS})
${fsa_r} : LIBS := $(filter-out -lterark-fsa-${COMPILER}-r, -L${BUILD_ROOT}/lib -lterark-core-${COMPILER}-r ${LIBS})


${zbs_d} : LIBS := -L${BUILD_ROOT}/lib -lterark-fsa-${COMPILER}-d -lterark-core-${COMPILER}-d ${LIBS}
${zbs_r} : LIBS := -L${BUILD_ROOT}/lib -lterark-fsa-${COMPILER}-r -lterark-core-${COMPILER}-r ${LIBS}

${zstd_d_o} ${zstd_r_o} : override CFLAGS += -Wno-sign-compare -Wno-implicit-fallthrough



${rpc_d} ${rpc_r} : LIBS += ${LIBBOOST} -lpthread
${rpc_d} : LIBS += -L${BUILD_ROOT}/lib -lterark-core-${COMPILER}-d
${rpc_r} : LIBS += -L${BUILD_ROOT}/lib -lterark-core-${COMPILER}-r

${fsa_d} : $(call objs,fsa,d) ${core_d}
${fsa_r} : $(call objs,fsa,r) ${core_r}
${static_fsa_d} : $(call objs,fsa,d)
${static_fsa_r} : $(call objs,fsa,r)

${zbs_d} : $(call objs,zbs,d) ${fsa_d} ${core_d}
${zbs_r} : $(call objs,zbs,r) ${fsa_r} ${core_r}
${static_zbs_d} : $(call objs,zbs,d)
${static_zbs_r} : $(call objs,zbs,r)

${rpc_d} : $(call objs,rpc,d) ${core_d}
${rpc_r} : $(call objs,rpc,r) ${core_r}
${static_rpc_d} : $(call objs,rpc,d)
${static_rpc_r} : $(call objs,rpc,r)

${core_d}:${core_d_o} 3rdparty/base64/lib/libbase64.o
${core_r}:${core_r_o} 3rdparty/base64/lib/libbase64.o
${static_core_d}:${core_d_o} 3rdparty/base64/lib/libbase64.o
${static_core_r}:${core_r_o} 3rdparty/base64/lib/libbase64.o


.PHONY: git-version.phony
${BUILD_ROOT}/git-version-%.cpp: git-version.phony
	@mkdir -p $(dir $@)
	@rm -f $@.tmp
	@echo '__attribute__ ((visibility ("default"))) const char*' \
		  'git_version_hash_info_'$(patsubst git-version-%.cpp,%,$(notdir $@))\
		  '() { return R"StrLiteral(git_version_hash_info_is:' > $@.tmp
	@env LC_ALL=C git log -n1 >> $@.tmp
	@env LC_ALL=C git diff >> $@.tmp
	@env LC_ALL=C $(CXX) --version >> $@.tmp
	@echo INCS = ${INCS}           >> $@.tmp
	@echo CXXFLAGS  = ${CXXFLAGS}  >> $@.tmp
	@echo WITH_BMI2 = ${WITH_BMI2} >> $@.tmp
	@echo WITH_TBB  = ${WITH_TBB}  >> $@.tmp
	@echo compile_cpu_flag: $(CPU) >> $@.tmp
	@#echo machine_cpu_flag: Begin  >> $@.tmp
	@#bash ./cpu_features.sh        >> $@.tmp
	@#echo machine_cpu_flag: End    >> $@.tmp
	@echo ')''StrLiteral";}' >> $@.tmp
	@#      ^^----- To prevent diff causing git-version compile fail
	@if test -f "$@" && cmp "$@" $@.tmp; then \
		rm $@.tmp; \
	else \
		mv $@.tmp $@; \
	fi

3rdparty/base64/lib/libbase64.o:
	$(MAKE) -C 3rdparty/base64 clean; \
	$(MAKE) -C 3rdparty/base64 lib/libbase64.o \
		CFLAGS="-fPIC -std=c99 -O3 -Wall -Wextra -pedantic"
		#AVX2_CFLAGS=-mavx2 SSE41_CFLAGS=-msse4.1 SSE42_CFLAGS=-msse4.2 AVX_CFLAGS=-mavx

%${DLL_SUFFIX}:
	@echo "----------------------------------------------------------------------------------"
	@echo "Creating dynamic library: $@"
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	@echo -e "OBJS:" $(addprefix "\n  ",$(sort $(filter %.o,$^)))
	@echo -e "LIBS:" $(addprefix "\n  ",${LIBS})
	mkdir -p ${BUILD_ROOT}/lib
	@rm -f $@
	${LD} -shared $(sort $(filter %.o,$^)) ${LDFLAGS} ${LIBS} -o ${CYG_DLL_FILE} ${CYGWIN_LDFLAGS}
	cd $(dir $@); ln -sf $(notdir $@) $(subst -${COMPILER},,$(notdir $@))
ifeq (CYGWIN, ${UNAME_System})
	@cp -l -f ${CYG_DLL_FILE} /usr/bin
endif

%.a:
	@echo "----------------------------------------------------------------------------------"
	@echo "Creating static library: $@"
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	@echo -e "OBJS:" $(addprefix "\n  ",$(sort $(filter %.o,$^) ${EXTRA_OBJECTS}))
	@echo -e "LIBS:" $(addprefix "\n  ",${LIBS})
	@mkdir -p ${BUILD_ROOT}/lib
	@rm -f $@
	${AR} rcs $@ $(filter %.o,$^) ${EXTRA_OBJECTS}
	cd $(dir $@); ln -sf $(notdir $@) $(subst -${COMPILER},,$(notdir $@))

.PHONY : install
install : core
	cp ${BUILD_ROOT}/lib/* ${prefix}/lib/

.PHONY : clean
clean:
	@for f in `find * -name "*${BUILD_NAME}*"`; do \
		echo rm -rf $${f}; \
		rm -rf $${f}; \
	done

.PHONY : cleanall
cleanall:
	@for f in `find * -name build`; do \
		echo rm -rf $${f}; \
		rm -rf $${f}; \
	done
	rm -rf pkg

.PHONY : depends
depends : ${alldep}

TarBallBaseName := terark-fsa_all-${BUILD_NAME}
TarBall := pkg/${TarBallBaseName}
.PHONY : pkg
.PHONY : tgz
pkg : ${TarBall}
tgz : ${TarBall}.tgz

${TarBall}: ${core} ${fsa} ${zbs}
	rm -rf ${TarBall}
	mkdir -p ${TarBall}/bin
	mkdir -p ${TarBall}/lib
	mkdir -p ${TarBall}/include/terark/io/win
	mkdir -p ${TarBall}/include/terark/util
	cp    src/terark/bits_rotate.hpp             ${TarBall}/include/terark
	cp    src/terark/config.hpp                  ${TarBall}/include/terark
	cp    src/terark/fstring.hpp                 ${TarBall}/include/terark
	cp    src/terark/lcast.hpp                   ${TarBall}/include/terark
	cp    src/terark/*hash*.hpp                  ${TarBall}/include/terark
	cp    src/terark/node_layout.hpp             ${TarBall}/include/terark
	cp    src/terark/num_to_str.hpp              ${TarBall}/include/terark
	cp    src/terark/parallel_lib.hpp            ${TarBall}/include/terark
	cp    src/terark/pass_by_value.hpp           ${TarBall}/include/terark
	cp    src/terark/stdtypes.hpp                ${TarBall}/include/terark
	cp    src/terark/valvec.hpp                  ${TarBall}/include/terark
	cp    src/terark/io/*.hpp                    ${TarBall}/include/terark/io
	cp    src/terark/io/win/*.hpp                ${TarBall}/include/terark/io/win
	cp    src/terark/util/*.hpp                  ${TarBall}/include/terark/util
ifeq (${PKG_WITH_DBG},1)
	cp    ${BUILD_ROOT}/lib/libterark-{fsa,zbs,core}-*d${DLL_SUFFIX} ${TarBall}/lib
  ifeq (${PKG_WITH_STATIC},1)
	mkdir -p ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib/libterark-zbs-{${COMPILER}-,}d.a ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib/libterark-fsa-{${COMPILER}-,}d.a ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib/libterark-core-{${COMPILER}-,}d.a ${TarBall}/lib_static
  endif
endif
	cp    ${BUILD_ROOT}/lib/libterark-{fsa,zbs,core}-*r${DLL_SUFFIX} ${TarBall}/lib
	echo $(shell date "+%Y-%m-%d %H:%M:%S") > ${TarBall}/package.buildtime.txt
	echo $(shell git log | head -n1) >> ${TarBall}/package.buildtime.txt
ifeq (${PKG_WITH_STATIC},1)
	mkdir -p ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib/libterark-zbs-{${COMPILER}-,}r.a ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib/libterark-fsa-{${COMPILER}-,}r.a ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib/libterark-core-{${COMPILER}-,}r.a ${TarBall}/lib_static
endif

${TarBall}.tgz: ${TarBall}
	cd pkg; tar czf ${TarBallBaseName}.tgz ${TarBallBaseName}

ifneq ($(MAKECMDGOALS),cleanall)
ifneq ($(MAKECMDGOALS),clean)
-include ${alldep}
endif
endif

${ddir}/%.o: %.cpp
	@echo file: $< "->" $@
	@echo TERARK_INC=${TERARK_INC}
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	mkdir -p $(dir $@)
	${CXX} ${CXX_STD} ${CPU} -c ${DBG_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${rdir}/%.o: %.cpp
	@echo file: $< "->" $@
	@echo TERARK_INC=${TERARK_INC}
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	mkdir -p $(dir $@)
	${CXX} ${CXX_STD} ${CPU} -c ${RLS_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${ddir}/%.o: %.cc
	@echo file: $< "->" $@
	@echo TERARK_INC=${TERARK_INC}
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	mkdir -p $(dir $@)
	${CXX} ${CXX_STD} ${CPU} -c ${DBG_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${rdir}/%.o: %.cc
	@echo file: $< "->" $@
	@echo TERARK_INC=${TERARK_INC}
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	mkdir -p $(dir $@)
	${CXX} ${CXX_STD} ${CPU} -c ${RLS_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${ddir}/%.o : %.c
	@echo file: $< "->" $@
	mkdir -p $(dir $@)
	${CC} -c ${CPU} ${DBG_FLAGS} ${CFLAGS} ${INCS} $< -o $@

${rdir}/%.o : %.c
	@echo file: $< "->" $@
	mkdir -p $(dir $@)
	${CC} -c ${CPU} ${RLS_FLAGS} ${CFLAGS} ${INCS} $< -o $@

${ddir}/%.s : %.cpp ${PRECOMPILED_HEADER_GCH}
	@echo file: $< "->" $@
	${CXX} -S -fverbose-asm ${CXX_STD} ${CPU} ${DBG_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${rdir}/%.s : %.cpp ${PRECOMPILED_HEADER_GCH}
	@echo file: $< "->" $@
	${CXX} -S -fverbose-asm ${CXX_STD} ${CPU} ${RLS_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${ddir}/%.s : %.c ${PRECOMPILED_HEADER_GCH}
	@echo file: $< "->" $@
	${CC} -S -fverbose-asm ${CPU} ${DBG_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${rdir}/%.s : %.c ${PRECOMPILED_HEADER_GCH}
	@echo file: $< "->" $@
	${CC} -S -fverbose-asm ${CPU} ${RLS_FLAGS} ${CXXFLAGS} ${INCS} $< -o $@

${rdir}/%.dep : %.c
	@echo file: $< "->" $@
	@echo INCS = ${INCS}
	mkdir -p $(dir $@)
	${CC} -M -MT $(basename $@).o ${INCS} $< > $@; true

${ddir}/%.dep : %.c
	@echo file: $< "->" $@
	@echo INCS = ${INCS}
	mkdir -p $(dir $@)
	${CC} -M -MT $(basename $@).o ${INCS} $< > $@; true

${rdir}/%.dep : %.cpp
	@echo file: $< "->" $@
	@echo INCS = ${INCS}
	mkdir -p $(dir $@)
	${CXX} ${CXX_STD} -M -MT $(basename $@).o ${INCS} $< > $@; true

${ddir}/%.dep : %.cpp
	@echo file: $< "->" $@
	@echo INCS = ${INCS}
	mkdir -p $(dir $@)
	${CXX} ${CXX_STD} -M -MT $(basename $@).o ${INCS} $< > $@; true
