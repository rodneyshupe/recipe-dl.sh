#!/usr/bin/env bash
trap 'rc=$?; echo "ERR at line ${LINENO} (rc: $rc)"; exit $rc' ERR
#trap 'rc=$?; echo "EXIT (rc: $rc)"; exit $rc' EXIT
set -u

SCRIPT_NAME=$0

TESTS=()

FAILURE_LOG_FILE=""

FLAG_DEBUG=0
FLAG_APPEND_LOG=0
FLAG_SILENT=0
FLAG_LOADTESTS=0
FLAG_APPENDTESTS=0

EX_OK=0            # successful termination
EX_USAGE=64        # command line usage error
EX_NOINPUT=66      # cannot open input
EX_OSFILE=72       # critical OS file missing
EX_IOERR=74        # input/output error

SCRIPT_PATH=$(dirname $(readlink $0) 2>/dev/null || dirname $0)           # relative
SCRIPT_PATH="`( cd \"${SCRIPT_PATH}\" && pwd )`"  # absolutized and normalized
if [ -z "${SCRIPT_PATH}" ] ; then
  echo_error "For some reason, the path is not accessible to the script (e.g. permissions re-evaled after suid)"
  exit ${EX_IOERR}  # fail
fi

PROJECT_PATH="`( cd \"${SCRIPT_PATH}/..\" && pwd )`"  # absolutized and normalized
if [ -z "${PROJECT_PATH}" ] ; then
  echo_error "For some reason, the path is not accessible to the script (e.g. permissions re-evaled after suid)"
  exit ${EX_IOERR}  # fail
fi
REFERENCE_FILE_PATH="${SCRIPT_PATH}/reference-files"
DEFAULT_TESTS_FILE="$SCRIPT_PATH/recipe-dl.tests"
DEFAULT_FAILURE_LOG_FILE="${SCRIPT_PATH}/test.failures.log"

COUNT_PASS=0
COUNT_FAIL=0
COUNT_SKIP=0

function usage {
  echo "Usage: ${SCRIPT_NAME} [-d] [-h] [-r] [-t <URL> <ReferenceFile>] [-t <URL> <ReferenceFile>] ..."
  if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "  -d|--debug                      Add additional Output"
    echo "  -h|--help                       Display help"
    echo "  -l|--log-file <FILE>            Specifiy Log File (Default: $DEFAULT_FAILURE_LOG_FILE) "
    echo "  -a|--append-log                 Append to existing log."
    echo "  -r|--reset-references           Instead of tests resets the reference files"
    echo "  -t|--test <URL> <ReferenceFile> URL to test. Overrides default tests."
    echo "     --load-tests <FILE>          load tests from file"
    echo "     --append-tests               Append manual tests to test file."
  fi
}

function parse_arguments () {
  TESTS=()
  FAILURE_LOG_FILE=""
  while (( "$#" )); do
    case "$1" in
      -d|--debug)
        FLAG_DEBUG=1
        shift
        ;;
      -h|--help)
        echo_info "$(usage)"
        exit 0
        ;;
      -r|--reset-references)
        reset_references
        shift
        exit 0
        ;;
      -l|--log-file)
        shift
        FAILURE_LOG_FILE="$1"
        shift
        ;;
      -a|--append-log)
        FLAG_APPEND_LOG=1
        shift
        ;;
      -t|--test)
        shift
        TESTS+=("$1|$2")
        shift
        shift
        ;;
      --load-tests)
        shift
        FLAG_LOADTESTS=1
        TESTS_FILE="${1}"
        load_tests "${TESTS_FILE}"
        shift
        ;;
      --append-tests)
        shift
        FLAG_APPENDTESTS=1
        ;;
      -*|--*=) # unsupported flags
        echo_error "ERROR: Unsupported flag $1"
        echo_error "$(usage)"
        exit ${EX_USAGE}
        ;;
      *) # preserve positional arguments
        echo_error "ERROR: Unsupported argument $1"
        echo_error "$(usage)"
        exit ${EX_USAGE}
        ;;
    esac
  done
  if [[ "${FAILURE_LOG_FILE}" == "" ]]; then
    FAILURE_LOG_FILE="${DEFAULT_FAILURE_LOG_FILE}"
  fi
  if [ ${#TESTS[@]} -eq 0 ]; then
    TESTS_FILE="${DEFAULT_TESTS_FILE}"
    load_tests "${TESTS_FILE}"
  fi
}

function command_exists() {
  command -v "$@" > /dev/null 2>&1
}

function echo_info() {
  echo "$@" >$(tty)
}

function echo_debug() {
  if [[ $FLAG_DEBUG -eq 1 ]]; then
    local _BREADCRUMB=$(basename ${SCRIPT_NAME})
    for (( idx=${#FUNCNAME[@]}-2 ; idx>=1 ; idx-- )) ; do
      _BREADCRUMB="${_BREADCRUMB}:${FUNCNAME[idx]}"
    done
    echo_info "[$(tput setaf 4; tput bold) DEBUG: ${_BREADCRUMB} $(tput sgr 0)] $@"
  fi
}

function echo_warning() {
  if [[ $FLAG_SILENT -eq 0 ]]; then
    local _BREADCRUMB=$(basename ${SCRIPT_NAME})
    for (( idx=${#FUNCNAME[@]}-2 ; idx>=1 ; idx-- )) ; do
      _BREADCRUMB="${_BREADCRUMB}:${FUNCNAME[idx]}"
    done
    echo_info "[$(tput setaf 3; tput bold) WARNING: ${_BREADCRUMB} $(tput sgr 0)] $@"
  fi
}

function echo_error() {
  local _BREADCRUMB=$(basename ${SCRIPT_NAME})
  for (( idx=${#FUNCNAME[@]}-1 ; idx>=1 ; idx-- )) ; do
    _BREADCRUMB="${_BREADCRUMB}:${FUNCNAME[idx]}"
  done
  echo_info "[$(tput setaf 1; tput bold) ERROR: ${_BREADCRUMB} $(tput sgr 0)] $@" >&2
}

function check_requirements() {
  local MISSING=""

  command_exists cmp || MISSING="${MISSING}$(echo '  cmp')"
  command_exists diff || MISSING="${MISSING}$(echo '  diff')"

  if [[ -n "${MISSING}" ]]; then
    echo_error "Script requires the following commands which are not installed."
    echo_error "${MISSING}"
    echo_error "Aborting."

    exit ${EX_OSFILE}
  fi
}

function option_from_file() {
  local _REFERENCE_FILE="${1}"

  echo_debug "Param: _REFERENCE_FILE=$_REFERENCE_FILE"
  local FILENAME=$(basename -- "$_REFERENCE_FILE")
  local EXTENTION="${FILENAME##*.}"
  #echo_debug "FILENAME=${FILENAME}"
  echo_debug "EXTENTION=${EXTENTION}"

  case "${EXTENTION}" in
    rst)
      OPTION="-r"
      ;;
    md)
      OPTION="-m"
      ;;
    json)
      OPTION="-j"
      ;;
  esac
  echo_debug "OPTION=${OPTION}"
  echo ${OPTION}
}

function load_tests() {
  local _TESTS_FILE=${1:-}

  if [ -s "${_TESTS_FILE}" ]; then
    echo_info "Loading tests from file: ${_TESTS_FILE}"
    TESTS=()
    IFS=
    while read -r TEST_LINE; do
      TEST_LINE="$(echo "${TEST_LINE}" | sed 's/\#.*$//g' | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g')"
      if [[ "${TEST_LINE}" != "" ]] ; then
        #echo_debug "Adding Test: \"${TEST_LINE}\"" #NOt sure why this is not working but is being added to the file 'not a tty'
        TESTS+=("${TEST_LINE}")
      fi
    done < "${_TESTS_FILE}"
    unset IFS
    echo_debug "Loaded ${#TESTS[@]} tests."
  else
    echo_error "Tests File (${_TESTS_FILE}) is missing."
    exit ${EX_NOINPUT}
  fi
  unset _TESTS_FILE
}

function append_tests() {
  if [ $FLAG_APPENDTESTS -ne 0 ] && [ ${#TESTS[@]} -gt 0 ]; then
    if [ $FLAG_LOADTESTS -ne 0 ]; then
      rm "${TESTS_FILE}" >/dev/null 2>&1
    fi
    for TEST in "${TESTS[@]}"; do
      echo "${TEST}" >> "${TESTS_FILE}"
    done
  fi
}

function log_failure() {
  local _OPTIONS="${1:-}"
  local _URL="${2}"
  local _REFERENCE_FILE="${3}"
  local _TMP_OUTPUT_FILE="${4}"
  echo_debug "  Params: _OPTIONS=${_OPTIONS}"
  echo_debug "  Params: _URL=${_URL}"
  echo_debug "  Params: _REFERENCE_FILE=${_REFERENCE_FILE}"
  echo_debug "  Params: _TMP_OUTPUT_FILE=${_TMP_OUTPUT_FILE}"

  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
  echo "Reference File: \"${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}\"" >> "${FAILURE_LOG_FILE}"
  echo "URL: \"${_URL}\"" >> "${FAILURE_LOG_FILE}"
  echo "" >> "${FAILURE_LOG_FILE}"
  echo "diff output below" >> "${FAILURE_LOG_FILE}"
  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
  diff --ignore-trailing-space --ignore-blank-lines "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${_TMP_OUTPUT_FILE}" >> "${FAILURE_LOG_FILE}"
  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
}

function reset_references {
  # Lopp through the tests
  for TEST in "${TESTS[@]}"; do
    local URL=$(cut -d'|' -f1 <<< "${TEST}")
    local REFERENCE_FILE=$(cut -d'|' -f2 <<< "${TEST}")

    local OPTION=$(option_from_file "${REFERENCE_FILE}")
    echo_info "  Resetting ${REFERENCE_FILE}"
    ${PROJECT_PATH}/recipe-dl.sh ${OPTION} -q -s -o "${REFERENCE_FILE_PATH}/${REFERENCE_FILE}" "${URL}" > /dev/null
    unset URL REFERENCE_FILE OPTION
  done
  unset TEST
}

function run_test() {
  local _URL="${1}"
  local _REFERENCE_FILE="${2:-}"

  local OPTION=$(option_from_file "${_REFERENCE_FILE}")
  local TMP_OUTPUT_FILE="$(mktemp ./test.output.XXXXXX)"
  rm "${TMP_OUTPUT_FILE}"

  echo_debug "Param: _URL=${_URL}"
  echo_debug "Param: _REFERENCE_FILE=${_REFERENCE_FILE}"
  echo_debug "Value: OPTION=${OPTION}"
  echo_debug "Value: TMP_OUTPUT_FILE=${TMP_OUTPUT_FILE}"

  local PRINT_WIDTH=$(tput cols)
  ((PRINT_WIDTH-=10))
  local PRINT_PARAM_WIDTH=$(($PRINT_WIDTH-13))
  local PRINT_OPTIONS=""
  PRINT_OPTIONS=$([ "${OPTION}" != "" ] && [ "${OPTION}" != " " ] && echo " (${OPTION})")
  local PRINT_URL=$(printf '%-'$(($PRINT_PARAM_WIDTH))'s' "${_URL}$PRINT_OPTIONS")
  if [ "${PRINT_URL:$(($PRINT_PARAM_WIDTH-1)):1}" == " " ]; then
    local PRINT_URL=$(printf '%.'$PRINT_PARAM_WIDTH's' "${_URL}${PRINT_OPTIONS}")
  else
    if [ "${PRINT_OPTIONS}" == "" ]; then
      PRINT_URL=$(printf '%.'$(($PRINT_PARAM_WIDTH-3))'s...' "${_URL}")
    else
      PRINT_URL=$(printf '%.'$(($PRINT_PARAM_WIDTH-8))'s...%s' "${_URL}" "${PRINT_OPTIONS}")
    fi
  fi
  printf 'Test: %-'$PRINT_PARAM_WIDTH's ' "${PRINT_URL}"

  if [ -s "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" ]; then
    ${PROJECT_PATH}/recipe-dl.sh ${OPTION} -q -s -o "${TMP_OUTPUT_FILE}" "${_URL}" > /dev/null

    local TMP_OUTPUT_FILE_EXT="$(set -- $TMP_OUTPUT_FILE.*; echo "$1")"
    echo_debug "Comapre File: \"$TMP_OUTPUT_FILE_EXT\""

    if diff --brief --ignore-trailing-space --ignore-blank-lines "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${TMP_OUTPUT_FILE_EXT}" >/dev/null ; then
      ((COUNT_PASS++))
      echo "[$(tput setaf 2; tput bold)PASS$(tput sgr 0)]"
    else
      ((COUNT_FAIL++))
      echo "[$(tput setaf 1; tput bold)FAIL$(tput sgr 0)] see log"
      log_failure "${OPTION}" "${_URL}" "${_REFERENCE_FILE}" "${TMP_OUTPUT_FILE_EXT}"
    fi
    rm "${TMP_OUTPUT_FILE_EXT}" 2>/dev/null
  else
    ((COUNT_SKIP++))
    echo "[$(tput setaf 3; tput bold)MISSING$(tput sgr 0)]"
    ${PROJECT_PATH}/recipe-dl.sh ${OPTION} -q -s -o "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${_URL}" > /dev/null
  fi
}

function run_tests() {
  echo_info "Running Tests..."
  if [ $FLAG_APPEND_LOG -eq 0 ] && [ ! -s $FLAG_APPEND_LOG ]; then
    echo_info "   Failues will be logged to $FAILURE_LOG_FILE"
    rm "$FAILURE_LOG_FILE" 2>/dev/null
  else
    echo_info "   Failues will be appended to $FAILURE_LOG_FILE"
  fi

  COUNT_PASS=0
  COUNT_FAIL=0
  COUNT_SKIP=0

  # Loop through the tests
  for TEST in "${TESTS[@]}"; do
    local URL=$(cut -d'|' -f1 <<< "${TEST}")
    local REFERENCE_FILE=$(cut -d'|' -f2 <<< "${TEST}")
    run_test "${URL}" "${REFERENCE_FILE}"
    unset URL REFERENCE_FILE
  done
  unset TEST
  echo_info ""
  echo_info "Results: ${COUNT_PASS} Passed  ${COUNT_FAIL} Failed  ${COUNT_SKIP} Skipped  "
}

check_requirements
parse_arguments "$@"
run_tests
append_tests
