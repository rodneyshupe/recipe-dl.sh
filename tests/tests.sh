#!/usr/bin/env bash
trap 'rc=$?; echo "ERR at line ${LINENO} (rc: $rc)"; exit $rc' ERR
#trap 'rc=$?; echo "EXIT (rc: $rc)"; exit $rc' EXIT
set -u

#Format for the below would be "Options|URL|ReferenceFile
DEFAULT_TESTS=( \
    "https://www.foodnetwork.com/recipes/chicken-wings-with-honey-and-soy-sauce-8662293|ChickenWingswithHoneyandSoySauce.rst"  \
    "https://www.bonappetit.com/recipe/instant-pot-split-pea-soup|InstantPotSplitPeaSoup.rst"  \
    "https://www.bonappetit.com/recipe/instant-pot-glazed-and-grilled-ribs|InstantPotGlazedandGrilledRibs.json" \
    "https://www.cooksillustrated.com/recipes/8800-sticky-buns|StickyBuns.rst" \
    "https://www.epicurious.com/recipes/food/views/instant-pot-macaroni-and-cheese|InstantPotMacaroniandCheese.md" \
    "https://www.saveur.com/perfect-brown-rice-recipe/|PerfectBrownRice.rst" \
    "https://www.saveur.com/lamb-ribs-with-spicy-harissa-barbecue-sauce-recipe/|LambRibsWithSpicyHarissaBarbecueSauceRecipe.json"
    "https://www.thechunkychef.com/easy-slow-cooker-mongolian-beef-recipe/|SlowCookerMongolianBeefRecipe.md" \
    "https://minimalistbaker.com/spicy-red-lentil-curry/|SpicyRedLentilCurry.rst" \
    "https://cooking.nytimes.com/recipes/1014366-chana-dal-new-delhi-style|ChanaDalNewDelhiStyle.rst" \
    "https://www.delish.com/cooking/recipe-ideas/recipes/a57660/instant-pot-mac-cheese-recipe/|InstantPotMacandCheese.json" \
    "https://www.cookingchanneltv.com/recipes/alton-brown/fondue-finally-reloaded-5496018|FondueFinallyReloaded.rst" \
    "https://www.finecooking.com/recipe/herbed-grill-roasted-lamb|HerbedGrillRoastedLamb.rst" \
    "https://www.food.com/recipe/annette-funicellos-peanut-butter-pork-12871|AnnetteFunicellosPeanutButterPork.rst" \
  )

TESTS=()

DEFAULT_FAILURE_LOG_FILE="./test.failures.log"
FAILURE_LOG_FILE=""

FLAG_DEBUG=0
FLAG_APPEND_LOG=0

PRINT_WIDTH=100

SCRIPT_NAME=$0

EX_OK=0            # successful termination
EX_USAGE=64        # command line usage error
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

function usage {
  echo "Usage: ${SCRIPT_NAME} [-d] [-h] [-r] [-t <URL> <ReferenceFile>] [-t <URL> <ReferenceFile>] ..."
  if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "  -d|--debug                      Add additional Output"
    echo "  -h|--help                       Display help"
    echo "  -l|--log-file <FILE>            Specifiy Log File (Default: $DEFAULT_FAILURE_LOG_FILE) "
    echo "  -a|--append-log                 Append to existing log."
    echo "  -r|--reset-references           Instead of tests resets the reference files"
    echo "  -t|--test <URL> <ReferenceFile> URL to test. Overrides default tests."
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
    TESTS=("${DEFAULT_TESTS[@]}")
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

    #TODO: Rather than Abort and exit, give option to install missing packages.
    # - For Debian, Ubuntu and Raspbian it will install the latest deb package.
    # - For Fedora, CentOS, RHEL and openSUSE it will install the latest rpm package.
    # - For Arch Linux it will install the AUR package.
    # - For any unrecognized Linux operating system it will install the latest standalone
    #   release into ~/.local
    #
    # - For macOS it will install the Homebrew package.
    #   - If Homebrew is not installed it will install the latest standalone release
    #     into ~/.local

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
  echo "The file \"${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}\" is different from output for \"${_URL}\"" >> "${FAILURE_LOG_FILE}"
  echo "diff output below" >> "${FAILURE_LOG_FILE}"
  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
  diff --ignore-trailing-space --ignore-blank-lines "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${_TMP_OUTPUT_FILE}" >> "${FAILURE_LOG_FILE}"
  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
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
    echo_debug "Actual File $TMP_OUTPUT_FILE_EXT"

    if diff --brief --ignore-trailing-space --ignore-blank-lines "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${TMP_OUTPUT_FILE_EXT}" >/dev/null ; then
      echo "[$(tput setaf 2; tput bold)PASS$(tput sgr 0)]"
    else
      echo "[$(tput setaf 1; tput bold)FAIL$(tput sgr 0)] see log"
      log_failure "${OPTION}" "${_URL}" "${_REFERENCE_FILE}" "${TMP_OUTPUT_FILE_EXT}"
    fi
    rm "${TMP_OUTPUT_FILE_EXT}" 2>/dev/null
  else
    echo "[$(tput setaf 3; tput bold)MISSING$(tput sgr 0)]"
    ${PROJECT_PATH}/recipe-dl.sh ${OPTION} -q -s -o "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${_URL}" > /dev/null
  fi
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

function run_tests() {
  if [ $FLAG_APPEND_LOG -eq 0 ] && [ ! -s $FLAG_APPEND_LOG ]; then
    rm "$FAILURE_LOG_FILE" 2>/dev/null
  fi
  # Loop through the tests
  for TEST in "${TESTS[@]}"; do
    local URL=$(cut -d'|' -f1 <<< "${TEST}")
    local REFERENCE_FILE=$(cut -d'|' -f2 <<< "${TEST}")

    run_test "${URL}" "${REFERENCE_FILE}"
    unset URL REFERENCE_FILE
  done
  unset TEST
}

parse_arguments "$@"
check_requirements
run_tests
