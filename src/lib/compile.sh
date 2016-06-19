# make sure to set MODE ("DEBUG", "PROFILE", or "RELEASE"), MAIN, and SRC before calling this
# you can add -Fu / -Fi lines to PATHS if you like
# you can add -dFOO to DEFINES if you like (for any value of FOO)
# you can set TESTCMD if you want to run a particular command instead of the obvious

# XXX -O4 should have LEVEL4 equivalent

PATHS="-FE${SRC}../bin/ -Fu${SRC}lib -Fi${SRC}lib ${PATHS}"
BINARY=`basename ${MAIN}`
if [ "${TESTCMD}" = "" ]; then TESTCMD="bin/${BINARY}"; fi

echo "compile: mode=${MODE} main=${MAIN} testcmd=${TESTCMD} defines=${DEFINES}"

ulimit -v 800000

if [ ! -f ${SRC}../bin/MODE.${MODE} ]
then
  echo "compile: Last compile mode was not ${MODE}, so wiping binary cache..."
  rm -rf ${SRC}../bin/*
  touch ${SRC}../bin/MODE.${MODE}
fi

if [ "${MODE}" = "DEBUG" ]
then

  # DEBUG MODE:
  echo compile: COMPILING - DEBUG MODE
  # add -vq to get warning numbers for {$WARN xxx OFF}
  fpc ${MAIN}.pas -l- -dDEBUG ${DEFINES} -Ci -Co -CO -Cr -CR -Ct -O- -gt -gl -gh -Sa -veiwnhb ${PATHS} 2>&1 | ${SRC}lib/filter.pl || exit 1
  cd ${SRC}.. &&
  #echo compile: Entering directory \`${PWD}/\' &&
  echo compile: Running ${TESTCMD} &&
  ${TESTCMD} || exit 1

elif [ "${MODE}" = "FAST-DEBUG" ]
then

  # FASTER DEBUG MODE:
  echo compile: COMPILING - DEBUG WITH OPTIMISATIONS
  fpc ${MAIN}.pas -l- -dDEBUG -dOPT ${DEFINES} -Ci -Co -CO -Cr -CR -Ct -O4 -gt -gl -Sa -veiwnhb ${PATHS} 2>&1 | ${SRC}lib/filter.pl || exit 1
  cd ${SRC}.. &&
  #echo compile: Entering directory \`${PWD}/\' &&
  echo compile: Running ${TESTCMD} &&
  ${TESTCMD} || exit 1

elif [ "${MODE}" = "FAST" ]
then

  # FASTER MODE:
  echo compile: COMPILING - SIMPLE OPTIMISATIONS ONLY, SYMBOL INFO INCLUDED
  fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -O4 -Xs- -gl -veiwnhb ${PATHS} 2>&1 | ${SRC}lib/filter.pl || exit 1
  cd ${SRC}.. &&
  #echo compile: Entering directory \`${PWD}/\' &&
  echo compile: Running ${TESTCMD} &&
  ${TESTCMD} || exit 1

elif [ "${MODE}" = "VALGRIND-DEBUG" ]
then

  echo compile: COMPILING - DEBUG BUILD WITH PROFILING ENABLED
  fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  until [ $? -eq 0 ]; do
    echo compile: Trying to find optimisation stable point...
    mv ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last || exit
    mv ${SRC}../bin/opt-feedback ${SRC}../bin/opt-feedback.last || exit
    fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -O4 -OwALL -Fw${SRC}../bin/opt-feedback.last -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} || exit 1
    cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  done
  echo compile: Final build...
  fpc ${MAIN}.pas -gv -a -l- -dOPT ${DEFINES} -gl -Xs -XX -B -O4 -v0einf -OwALL -Fw${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  rm -f ${SRC}../bin/*.o ${SRC}../bin/*.ppu ${SRC}../bin/*.last &&
  ls -al ${SRC}../bin/${BINARY} &&
  perl -E 'say ("executable size: " . (-s $ARGV[0]) . " bytes")' ${SRC}../bin/${BINARY} &&
  cd ${SRC}.. &&
  #echo compile: Entering directory \`${PWD}/\' &&
  echo compile: Running ${TESTCMD} &&
  ${TESTCMD} || exit 1

elif [ "${MODE}" = "PROFILE" ]
then

  # PROFILE MODE:
  echo compile: COMPILING - OPTIMISED BUILD WITH PROFILING ENABLED
  fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  until [ $? -eq 0 ]; do
    echo compile: Trying to find optimisation stable point...
    mv ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last || exit
    mv ${SRC}../bin/opt-feedback ${SRC}../bin/opt-feedback.last || exit
    fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -O4 -OwALL -Fw${SRC}../bin/opt-feedback.last -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} || exit 1
    cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  done
  echo compile: Final build...
  fpc ${MAIN}.pas -gv -a -l- -dOPT ${DEFINES} -Xs -XX -B -O4 -v0einf -OwALL -Fw${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  rm -f ${SRC}../bin/*.o ${SRC}../bin/*.ppu ${SRC}../bin/*.last ${SRC}../bin/callgrind.out &&
  cd ${SRC}.. &&
  echo compile: Running valgrind --tool=callgrind ${TESTCMD} &&
  valgrind --tool=callgrind --callgrind-out-file=bin/callgrind.out ${TESTCMD};
  callgrind_annotate --auto=yes --inclusive=yes --tree=both bin/callgrind.out > callgrind.inclusive.txt
  callgrind_annotate --auto=yes --inclusive=no --tree=none bin/callgrind.out > callgrind.exclusive.txt

elif [ "${MODE}" = "MEMCHECK" ]
then

  # MEMCHECK MODE:
  echo compile: COMPILING - OPTIMISED BUILD WITH PROFILING ENABLED
  fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  until [ $? -eq 0 ]; do
    echo compile: Trying to find optimisation stable point...
    mv ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last || exit
    mv ${SRC}../bin/opt-feedback ${SRC}../bin/opt-feedback.last || exit
    fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -O4 -OwALL -Fw${SRC}../bin/opt-feedback.last -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} || exit 1
    cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  done
  echo compile: Final build...
  fpc ${MAIN}.pas -gv -a -l- -dOPT ${DEFINES} -Xs -XX -B -O4 -v0einf -OwALL -Fw${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  rm -f ${SRC}../bin/*.o ${SRC}../bin/*.ppu ${SRC}../bin/*.last ${SRC}../bin/callgrind.out &&
  cd ${SRC}.. &&
  echo compile: Running valgrind --tool=memcheck ${TESTCMD} &&
  valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes --log-file=memcheck.txt ${TESTCMD};

else

  # RELEASE MODE:
  echo compile: COMPILING - RELEASE MODE
  fpc ${MAIN}.pas -l- -dRELEASE -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  until [ $? -eq 0 ]; do
    echo compile: Trying to find optimisation stable point...
    mv ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last || exit
    mv ${SRC}../bin/opt-feedback ${SRC}../bin/opt-feedback.last || exit
    fpc ${MAIN}.pas -l- -dRELEASE -dOPT ${DEFINES} -Xs- -XX -B -O4 -OwALL -Fw${SRC}../bin/opt-feedback.last -OWALL -FW${SRC}../bin/opt-feedback ${PATHS} || exit 1
    cmp -s ${SRC}../bin/${BINARY} ${SRC}../bin/${BINARY}.last
  done
  echo compile: Final build...
  fpc ${MAIN}.pas -a -l- -dRELEASE -dOPT ${DEFINES} -Xs -XX -B -O4 -v0einf -OwALL -Fw${SRC}../bin/opt-feedback ${PATHS} 2>&1 || exit 1
  rm -f ${SRC}../bin/*.o ${SRC}../bin/*.ppu ${SRC}../bin/*.last &&
  ls -al ${SRC}../bin/${BINARY} &&
  perl -E 'say ("executable size: " . (-s $ARGV[0]) . " bytes")' ${SRC}../bin/${BINARY} &&
  cd ${SRC}.. &&
  #echo compile: Entering directory \`${PWD}/\' &&
  echo compile: Running ${TESTCMD} &&
  time ${TESTCMD} || exit 1

fi
