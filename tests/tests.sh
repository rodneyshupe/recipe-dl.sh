#!/usr/bin/env bash

#Format for the below would be "Options|URL|ReferenceFile
TESTS=(" |https://www.foodnetwork.com/recipes/chicken-wings-with-honey-and-soy-sauce-8662293|ChickenWingswithHoneyandSoySauce.rst"  \
       "-r|https://www.bonappetit.com/recipe/instant-pot-split-pea-soup|InstantPotSplitPeaSoup.rst"  \
       "-r|https://www.cooksillustrated.com/recipes/8800-sticky-buns|StickyBuns.rst" \
       "-m|https://www.epicurious.com/recipes/food/views/instant-pot-macaroni-and-cheese|InstantPotMacaroniandCheese.md" \
       "-r|https://cooking.nytimes.com/recipes/1014366-chana-dal-new-delhi-style|ChanaDalNewDelhiStyle.rst" \
       "-j|https://www.delish.com/cooking/recipe-ideas/recipes/a57660/instant-pot-mac-cheese-recipe/|InstantPotMacandCheese.json" \
       "-r|https://www.food.com/recipe/annette-funicellos-peanut-butter-pork-12871|AnnetteFunicellosPeanutButterPork.rst" )

FLAG_DEBUG=1

EX_OSFILE=72       # critical OS file missing

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
    echo_info "[$(tput setaf 3; tput bold) DEBUG: ${_BREADCRUMB} $(tput sgr 0)] $@"
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

SCRIPT_PATH=$(dirname $(readlink $0) 2>/dev/null || dirname $0)           # relative
SCRIPT_PATH="`( cd \"${SCRIPT_PATH}\" && pwd )`"  # absolutized and normalized
if [ -z "${SCRIPT_PATH}" ] ; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1  # fail
fi

PROJECT_PATH="`( cd \"${SCRIPT_PATH}/..\" && pwd )`"  # absolutized and normalized
if [ -z "${PROJECT_PATH}" ] ; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1  # fail
fi
REFERENCE_FILE_PATH="${SCRIPT_PATH}/reference-files"

function log_failure() {
  local _OPTIONS="${1:-}"
  local _URL="${2}"
  local _REFERENCE_FILE="${3}"
  local _TMP_OUTPUT_FILE="${4}"
  echo_debug "  Params: _OPTIONS=${_OPTIONS}"
  echo_debug "  Params: _URL=${_URL}"
  echo_debug "  Params: _REFERENCE_FILE=${_REFERENCE_FILE}"
  echo_debug "  Params: _TMP_OUTPUT_FILE=${_TMP_OUTPUT_FILE}"

  local FAILURE_LOG_FILE="./test.failures.log"

  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
  echo "The file \"${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}\" is different from output for \"${_URL}\"" >> "${FAILURE_LOG_FILE}"
  echo "diff output below" >> "${FAILURE_LOG_FILE}"
  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
  diff --ignore-trailing-space --ignore-blank-lines "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${_TMP_OUTPUT_FILE}" >> "${FAILURE_LOG_FILE}"
  echo "======================================================================================================" >> "${FAILURE_LOG_FILE}"
}

function run_test() {
  local _OPTIONS="${1:-}"
  local _URL="${2}"
  local _REFERENCE_FILE="${3:-}"

  local TMP_OUTPUT_FILE="$(mktemp ./test.output.XXXXXX)"

  echo_debug "  Params: _OPTIONS=${_OPTIONS}"
  echo_debug "  Params: _URL=${_URL}"
  echo_debug "  Params: _REFERENCE_FILE=${_REFERENCE_FILE}"
  echo_debug "  Value: TMP_OUTPUT_FILE=${TMP_OUTPUT_FILE}"

  PRINT_WIDTH=100
  PRINT_PARAM_WIDTH=$(($PRINT_WIDTH-13))
  PRINT_OPTIONS=""
  PRINT_OPTIONS=$([ "${_OPTIONS}" != "" ] && [ "${_OPTIONS}" != " " ] && echo " (${_OPTIONS})")
  PRINT_URL=$(printf '%-'$(($PRINT_PARAM_WIDTH))'s' "${_URL}$PRINT_OPTIONS")
  if [ "${PRINT_URL:$(($PRINT_PARAM_WIDTH-1)):1}" == " " ]; then
    PRINT_URL=$(printf '%.'$PRINT_PARAM_WIDTH's' "${_URL}${PRINT_OPTIONS}")
  else
    if [ "${PRINT_OPTIONS}" == "" ]; then
      PRINT_URL=$(printf '%.'$(($PRINT_PARAM_WIDTH-3))'s...' "${_URL}")
    else
      PRINT_URL=$(printf '%.'$(($PRINT_PARAM_WIDTH-8))'s...%s' "${_URL}" "${PRINT_OPTIONS}")
    fi
  fi
  printf 'Test: %-'$PRINT_PARAM_WIDTH's ' "${PRINT_URL}"

  ${PROJECT_PATH}/recipe-dl.sh ${_OPTIONS} -q -s -o "${TMP_OUTPUT_FILE}" "${_URL}" > /dev/null

  TMP_OUTPUT_FILE_EXT="$(set -- $TMP_OUTPUT_FILE.*; echo "$1")"
  echo_debug "Actual File $TMP_OUTPUT_FILE_EXT"

  echo_debug "Comparing to: ${_REFERENCE_FILE}"

  if diff --brief --ignore-trailing-space --ignore-blank-lines "${REFERENCE_FILE_PATH}/${_REFERENCE_FILE}" "${TMP_OUTPUT_FILE_EXT}" >/dev/null ; then
    echo "[$(tput setaf 2; tput bold)PASS$(tput sgr 0)]"
  else
    echo "[$(tput setaf 1; tput bold)FAIL$(tput sgr 0)] see log"
    log_failure "${_OPTIONS}" "${_URL}" "${_REFERENCE_FILE}" "${TMP_OUTPUT_FILE_EXT}"
  fi
  rm "${TMP_OUTPUT_FILE}"
  rm "${TMP_OUTPUT_FILE_EXT}"
}

check_requirements

#Lopp through the tests
for TEST in "${TESTS[@]}"
do
  OPTIONS=$(cut -d'|' -f1 <<< "${TEST}")
  URL=$(cut -d'|' -f2 <<< "${TEST}")
  REFERENCE=$(cut -d'|' -f3 <<< "${TEST}")

  run_test "${OPTIONS}" "${URL}" "${REFERENCE}"
  unset IFS
done
