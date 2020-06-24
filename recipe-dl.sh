#!/usr/bin/env bash
trap 'rc=$?; echo "ERR at line ${LINENO} (rc: $rc)"; exit $rc' ERR
#trap 'rc=$?; echo "EXIT (rc: $rc)"; exit $rc' EXIT
set -u
#set -E

# Requires curl, jq, hxnormalize, hxselect

# Exmples:
#   ./recipe-dl.sh -s https://www.cooksillustrated.com/recipes/8800-sticky-buns
#   ./recipe-dl.sh https://cooking.nytimes.com/recipes/1019530-cajun-shrimp-boil
#   ./recipe-dl.sh https://www.foodnetwork.com/recipes/chicken-wings-with-honey-and-soy-sauce-8662293
#   ./recipe-dl.sh https://www.saveur.com/lamb-ribs-with-spicy-harissa-barbecue-sauce-recipe/

# Script Constant
declare -r SCRIPT_NAME=$0

# EXIT CODES
declare -r -i EX_OK=0            # successful termination
declare -r -i EX_USAGE=64        # command line usage error
declare -r -i EX_DATAERR=65      # data format error
declare -r -i EX_NOINPUT=66      # cannot open input
# declare -r -i EX_NOUSER=67       # addressee unknown
# declare -r -i EX_NOHOST=68       # host name unknown
# declare -r -i EX_UNAVAILABLE=69  # service unavailable
declare -r -i EX_SOFTWARE=70     # internal software error
# declare -r -i EX_OSERR=71        # system error (e.g., can't fork)
declare -r -i EX_OSFILE=72       # critical OS file missing
declare -r -i EX_CANTCREAT=73    # can't create (user) output file
# declare -r -i EX_IOERR=74        # input/output error
# declare -r -i EX_TEMPFAIL=75     # temp failure; user is invited to retry
# declare -r -i EX_PROTOCOL=76     # remote error in protocol
declare -r -i EX_NOPERM=77       # permission denied
# declare -r -i EX_CONFIG=78       # configuration error

# Flags
declare -i FLAG_SAVE_TO_FILE=0
declare -i FLAG_DEBUG=0
declare -i FLAG_SILENT=0
declare -i FLAG_AUTHORIZE=0
declare -i FLAG_OUTPUT_JSON=0
declare -i FLAG_OUTPUT_MD=0
declare -i FLAG_OUTPUT_RST=0

# Arguments
declare ARG_IN_FiLE=""
declare ARG_OUT_FiLE=""
declare ARG_PASSED_URLS=""

function usage {
  echo "Usage: ${SCRIPT_NAME} [-ahjmros] [-f infile] [-o outfile] <URL> [<URL] ..."
  if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "  -a|--authorize         Force authorization of Cook Illustrated sites"
    echo "  -d|--debug             Add additional Output"
    echo "  -q|--quite             Suppress most output aka Silent Mode"
    echo "  -h|--help              Display help"
    echo "  -j|--output-json       Output results in JSON format"
    echo "  -m|--output-md         Output results in Markdown format"
    echo "  -r|--output-rst        Output results in reSTructuredText format"
    echo "  -i|--infile infile     Specify input json file infile"
    echo "  -o|--outfile outfile   Specify output file outfile"
    echo "  -s|--save-to-file      Save output file(s)"
  fi
}

function parse_arguments () {
  while (( "$#" )); do
    case "$1" in
      -d|--debug)
        FLAG_DEBUG=1
        shift
        ;;
      -q|--silent)
        FLAG_SILENT=1
        shift
        ;;
      -s|--save-to-file)
        FLAG_SAVE_TO_FILE=1
        shift
        ;;
      -j|--output-json)
        FLAG_OUTPUT_JSON=1
        shift
        ;;
      -m|--output-md)
        FLAG_OUTPUT_MD=1
        shift
        ;;
      -r|--output-rst)
        FLAG_OUTPUT_RST=1
        shift
        ;;
      -i|--infile)
        shift
        ARG_IN_FiLE=$1
        shift
        ;;
      -o|--outfile)
        FLAG_SAVE_TO_FILE=1
        shift
        ARG_OUT_FiLE=$1
        shift
        ;;
      -a|--authorize)
        FLAG_AUTHORIZE=1
        shift
        ;;
      -h|--help)
        echo_info "$(usage)"
        shift
        exit 0
        ;;
      -*|--*=) # unsupported flags
        echo_error "ERROR: Unsupported flag $1"
        echo_error "$(usage)"
        exit ${EX_USAGE}
        ;;
      *) # preserve positional arguments
        ARG_PASSED_URLS="${ARG_PASSED_URLS} $1"
        shift
        ;;
    esac
  done

  if [ ${FLAG_DEBUG} -eq 1 ] && [ ${FLAG_SILENT} -eq 1 ]; then
    FLAG_SILENT=0
    echo_info "Debug option selected. Can not run in \"Silent Mode\""
  fi

  FILETYPE_COUNT=0
  [[ ${FLAG_OUTPUT_JSON} -eq 1 ]] && ((FILETYPE_COUNT++))
  [[ ${FLAG_OUTPUT_MD} -eq 1 ]] && ((FILETYPE_COUNT++))
  [[ ${FLAG_OUTPUT_RST} -eq 1 ]] && ((FILETYPE_COUNT++))

  [[ ${FILETYPE_COUNT} -eq 0 ]] && FLAG_OUTPUT_RST=1
  if [[ ${FILETYPE_COUNT} -gt 1 ]] && [[ ${FLAG_SAVE_TO_FILE} -eq 0 ]]; then
    echo_info "INFO: More than one output file type select. Assuming 'Save to File'"
    FLAG_SAVE_TO_FILE=1
  fi

  if [ -z "${ARG_PASSED_URLS}" ]; then
      echo_error "$(usage 'SHORT')"
      exit ${EX_USAGE}
  fi
}

function command_exists() {
  command -v "$@" > /dev/null 2>&1
}

function echo_info() {
  if [[ $FLAG_SILENT -eq 0 ]]; then
    echo "$@" >$(tty)
  fi
}

function echo_debug() {
  if [[ $FLAG_DEBUG -ne 0 ]]; then
    local _BREADCRUMB=$(basename ${SCRIPT_NAME})
    for (( idx=${#FUNCNAME[@]}-2 ; idx>=1 ; idx-- )) ; do
      _BREADCRUMB="${_BREADCRUMB}:${FUNCNAME[idx]}"
    done
    echo_info "[$(tput setaf 4; tput bold) DEBUG: ${_BREADCRUMB} $(tput sgr 0)] $@"
  fi
}

function echo_warning() {
  if [[ $FLAG_SILENT -eq 0 ]]; then
    local _BREADCRUMB=""
    if [[ $FLAG_DEBUG -ne 0 ]]; then
      _BREADCRUMB=$(basename ${SCRIPT_NAME})
      for (( idx=${#FUNCNAME[@]}-1 ; idx>=1 ; idx-- )) ; do
        _BREADCRUMB="${_BREADCRUMB}:${FUNCNAME[idx]}"
      done
      _BREADCRUMB=": ${_BREADCRUMB}"
    fi
    echo_info "[$(tput setaf 3; tput bold) WARNING${_BREADCRUMB} $(tput sgr 0)] $@"
  fi
}

function echo_error() {
  local _BREADCRUMB=""
  if [[ $FLAG_DEBUG -ne 0 ]]; then
    _BREADCRUMB=$(basename ${SCRIPT_NAME})
    for (( idx=${#FUNCNAME[@]}-1 ; idx>=1 ; idx-- )) ; do
      _BREADCRUMB="${_BREADCRUMB}:${FUNCNAME[idx]}"
    done
    _BREADCRUMB=": ${_BREADCRUMB}"
  fi
  echo_info "[$(tput setaf 1; tput bold) ERROR${_BREADCRUMB} $(tput sgr 0)] $@" >&2
}

function rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}

function rawtime2minutes() {
  _TIME="${1:-}"

  if [[ ${_TIME} != null ]] && [[ -n "${_TIME}" ]]; then
    local HOURS=0
    local MINUTES=0
    local HOURS_RAW=$(echo "${_TIME}" | sed 's/^P.*T\([0-9]*\)H.*/\1/g')
    local MINUTES_RAW=$(echo "${_TIME}" | sed 's/^P.*[H,T]\([0-9]*\)M.*/\1/g')

    if [[ -n "${HOURS_RAW}" ]] && [ -n "$HOURS_RAW" ] && [ "$HOURS_RAW" -eq "$HOURS_RAW" ] 2>/dev/null; then
      HOURS=$(( ${HOURS_RAW} ))
    fi
    if [[ -n "${MINUTES_RAW}" ]] && [ -n "$MINUTES_RAW" ] && [ "$MINUTES_RAW" -eq "$MINUTES_RAW" ] 2>/dev/null; then
      MINUTES=$(( ${MINUTES_RAW} ))
    fi

    TOTAL_MINUTES=$((${HOURS}*60+${MINUTES}))
  else
    TOTAL_MINUTES=0
  fi
  echo $(( $TOTAL_MINUTES ))
}

function minutes2time() {
  _MINUTES=$1

  local TIME=""

  if [[ -n "${_MINUTES}" ]] && [[ ${_MINUTES} != null ]] && [[ ${_MINUTES} -gt 0 ]]; then
    local HOUR=$(( ${_MINUTES}/60 ))
    local MINUTES=$(( ${_MINUTES}-(( ${HOUR}*60 )) ))

    if [[ ${HOUR} -gt 0 ]]; then
      if [[ ${HOUR} -gt 1 ]]; then
        TIME="${HOUR} hours "
      else
        TIME="${HOUR} hour "
      fi
    fi
    if [[ ${MINUTES} -gt 0 ]]; then
      if [[ ${MINUTES} -gt 1 ]]; then
        TIME="${TIME}${MINUTES} minutes"
      else
        TIME="${TIME}${MINUTES} minute"
      fi
    fi
  else
    TIME="TBD"
  fi
  echo "${TIME}"
}

function check_requirements() {
  local MISSING=""

  command_exists curl || MISSING="${MISSING}$(echo '  curl')"
  command_exists jq || MISSING="${MISSING}$(echo '  jq')"
  command_exists hxselect || MISSING="${MISSING}$(echo '  hxnormalize and hxselect (packaged in html-xml-utils)')"

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

function install_macos() {
  if command_exists brew; then
    echo_info "Installing from Homebrew..."
    echo_info

    brew install $@ >$(tty)

    return
  elif command_exists port; then
    echo_info "Installing from MacPorts..."
    echo_info

    port install $@ >$(tty)

    return
  fi

  echo_error "Homebrew not installed."
  echo_error "Aborting."
}

function install_deb() {
  echo_info "Installing $@..."
  echo_info

  sudo_sh_c apt-get install -y $@
}

function install_rpm() {
  echo_info "Installing $@..."
  echo_info

  sudo_sh_c sudo dnf install $@ #Fedora
  sudo zypper install $@ #openSUSE
}

function install_aur() {
  echo_info "Installing $@..."
  echo_info
  sudo pacman -S $@
}

function url2domain() {
  _URL=${1:-}
  echo_debug "_URL=${_URL}"

  local DOMAIN=$(echo "${_URL}" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
  echo_debug "DOMAIN=${DOMAIN}"

  echo "${DOMAIN}"
  unset _URL DOMAIN
}

function domain2publisher() {
  _URL=$1

  echo_debug "_URL=${_URL}"

  case "$(url2domain "${_URL}")" in
    www.americatestkitchen.com)
      PUBLISHER="America's Test Kitchen"
      ;;
    www.cookscountry.com)
      PUBLISHER="Cook's Country"
      ;;
    www.cooksillustrated.com)
      PUBLISHER="Cook's Illustrated"
      ;;
    www.epicurious.com)
      PUBLISHER="Epicurious"
      ;;
    www.bonappetit.com)
      PUBLISHER="Bon Appétit"
      ;;
    www.foodnetwork.com)
      PUBLISHER="Food Network"
      ;;
    cooking.nytimes.com)
      PUBLISHER="New York Times"
      ;;
    www.food.com)
      PUBLISHER="Food.com"
      ;;
    www.saveur.com)
      PUBLISHER="Saveur"
      ;;
    * )
      PUBLISHER=""
  esac

  echo "${PUBLISHER}"
}

function authorize_ci() {
  echo_debug "Authorizing Cooks Illustrated..."
  _COOKIE_FILE=$1
  _AUTH_DOMAIN=$2

  local NEXT_PAGE="$(rawurlencode $3)"

  echo_debug "   _COOKIE_FILE=${_COOKIE_FILE}"
  echo_debug "   _AUTH_DOMAIN=${_AUTH_DOMAIN}"
  echo_debug "   NEXT_PAGE=${3}"

  echo_info "   Get authorization from ${_AUTH_DOMAIN}..."

  local TMP_HTML_FILE="$(mktemp /tmp/${FUNCNAME[0]}_signin.html.XXXXXX)"
  local TMP_POSTDATA="$(mktemp /tmp/${FUNCNAME[0]}_postdata.txt.XXXXXX)"

  curl --compressed --silent --cookie-jar ${_COOKIE_FILE} https://${_AUTH_DOMAIN}/sign_in?next=${NEXT_PAGE} | sed -n '/<form class="appForm" novalidate="novalidate" autocomplete="off" action="\/sessions"/,/<\/form>/p' > $TMP_HTML_FILE

  rm ${TMP_POSTDATA}
  IFS=$'\n'
  for INPUT_HTML_TAG in $(cat $TMP_HTML_FILE | sed -e $'s/<input/\\\n<input/g' | grep '<input'); do
    echo -ne $(echo ${INPUT_HTML_TAG} | sed -E 's/.* name=\"([^\"]*)\".* value=\"([^\"]*)\".*/\1=/g') >> ${TMP_POSTDATA}
    echo $(rawurlencode "$(echo ${INPUT_HTML_TAG} | sed -E 's/.* name=\"([^\"]*)\".* value=\"([^\"]*)\".*/\2/g')") >> ${TMP_POSTDATA}
  done
  unset \
    INPUT_HTML_TAG \
    IFS

  # Prompt for Username and password
  read -p "Enter email: " USER_EMAIL
  read -s -p "Enter Password: " USER_PASS

  local USER_EMAIL="$(rawurlencode ${USER_EMAIL})"
  local USER_PASS="$(rawurlencode ${USER_PASS})"

  sed -i -e 's/user\[email\]=/user\[email\]='${USER_EMAIL}'/g' ${TMP_POSTDATA}
  sed -i -e 's/user\[password\]=/user\[password\]='${USER_PASS}'/g' ${TMP_POSTDATA}

  echo "$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\&/g' ${TMP_POSTDATA})" > ${TMP_POSTDATA}

  curl --compressed --silent --list-only --data @${TMP_POSTDATA} --cookie-jar ${_COOKIE_FILE} --cookie ${_COOKIE_FILE} https://${_AUTH_DOMAIN}/sessions?next=${NEXT_PAGE} > /tmp/cisessions.html
}

function get_ci_page () {
  echo_debug "Retriving Cooks Illustrated"

  _URL=$1
  _HTML_FILE=$2

  echo_debug "   _URL=${_URL}"
  echo_debug "   _HTML_FILE=${_HTML_FILE}"

  local SCRIPT_PATH="`dirname \"${0}\"`"              # relative
  local SCRIPT_PATH="`( cd \"${SCRIPT_PATH}\" && pwd )`"  # absolutized and normalized
  if [ -z "${SCRIPT_PATH}" ] ; then
    # error; for some reason, the path is not accessible
    # to the script (e.g. permissions re-evaled after suid)
    SCRIPT_PATH="."
  fi

  local DOMAIN=$(url2domain "${_URL}")
  local COOKIE_FILE="${SCRIPT_PATH}/.${DOMAIN}.cookies"

  echo_info "   Using Cookie file: ${COOKIE_FILE}"
  [[ -f "${COOKIE_FILE}" ]] || FLAG_AUTHORIZE=1
  if [[ ${FLAG_AUTHORIZE} -eq 1 ]]; then
    authorize_ci "${COOKIE_FILE}" "${DOMAIN}" "${_URL}"
  fi
  curl --compressed --silent --cookie ${COOKIE_FILE} ${_URL} | hxnormalize -x > ${_HTML_FILE}
}

function ci2json() {
  echo_debug "Building JSON from Cooks Illustrated Page..."
  _URL=$1
  echo_debug "   _URL=${_URL}"

  local TMP_SOURCE_HTML_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.html.XXXXXX)"
  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  local TMP_SOURCE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_data.json.XXXXXX)"

  get_ci_page ${_URL} ${TMP_SOURCE_HTML_FILE}
  cat "${TMP_SOURCE_HTML_FILE}" | hxselect -i -c 'script#__NEXT_DATA__' > ${TMP_SOURCE_JSON_FILE} 2>/dev/null

  if [[ $? -ne 0 ]]; then
    if [[ ${FLAG_AUTHORIZE} -eq 0 ]]; then
      DOMAIN=$(url2domain "${_URL}")
      COOKIE_FILE="${SCRIPT_PATH}/.${DOMAIN}.cookies"
      authorize_ci "${COOKIE_FILE}" "${DOMAIN}" "${_URL}"
      get_ci_page ${_URL} ${TMP_SOURCE_HTML_FILE}
      cat "${TMP_SOURCE_HTML_FILE}" | hxselect -i -c 'script#__NEXT_DATA__' > ${TMP_SOURCE_JSON_FILE} 2>/dev/null
      [[ $? -ne 0 ]] && echo_error "   ERROR: Problem reading source." ; exit ${EX_NOINPUT}
    else
      FLAG_AUTHORIZE=0
      get_ci_page ${_URL} ${TMP_SOURCE_HTML_FILE}
      cat "${TMP_SOURCE_HTML_FILE}" | hxselect -i -c 'script#__NEXT_DATA__' > ${TMP_SOURCE_JSON_FILE} 2>/dev/null
      [[ $? -ne 0 ]] && echo_error "   ERROR: Problem reading source." ; exit ${EX_NOINPUT}
    fi
  fi

  echo "{" > "${TMP_RECIPE_JSON_FILE}"

  echo "  \"url\": \"$_URL\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"title\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .props.initialState.content.documents | jq --raw-output .[].title)\"," >> "${TMP_RECIPE_JSON_FILE}"

  echo "  \"description\": \"$(echo $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .props.initialState.content.documents | jq -c .[].metaData.fields.description) | sed 's/\\r//g' | sed 's/\\n/ /g' | sed 's/^\\\"//g' | sed 's/<[^>]*>//g' | sed 's/^\"\(.*\)\"$/\1/g' | sed 's/\"/\\\"/g')\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"yield\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .props.initialState.content.documents | jq --raw-output .[].yields)\"," >> "${TMP_RECIPE_JSON_FILE}"

  #TODO: Parse Time
  echo "  \"preptime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"cooktime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  local TOTAlTIME=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .props.initialState.content.documents | jq --raw-output .[].recipeTimeNote)
  [[ ${TOTAlTIME} == null ]] && TOTAlTIME="TBD"
  echo "  \"totaltime\": \"${TOTAlTIME}\"," >> "${TMP_RECIPE_JSON_FILE}"

  local AUTHOR=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .props.initialState.content.documents | jq --raw-output .[].metaData.fields.source)
  if [[ ${AUTHOR} == null ]]; then
    AUTHOR="$(domain2publisher "${URL}")"
  fi
  echo "  \"author\": \"${AUTHOR}\"," >> "${TMP_RECIPE_JSON_FILE}"

  # Ingredient Groups and ingredients
  echo "  \"ingredient_groups\": [" >> "${TMP_RECIPE_JSON_FILE}"

  IFS=$'\n'
  local group_index=-1
  for grouptitle in $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .props.initialState.content.documents | jq --raw-output .[].ingredientGroups[].fields.title); do
    ((group_index++))
    echo "    $([[ $group_index -gt 0 ]] && echo ', '){" >> "${TMP_RECIPE_JSON_FILE}"

    if [[ ${grouptitle} != null ]]; then
      echo "      \"title\":\"${grouptitle}\"," >> "${TMP_RECIPE_JSON_FILE}"
    else
      echo "      \"title\":\"\"," >> "${TMP_RECIPE_JSON_FILE}"
    fi
    echo "      \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
    local ingredient_count=0
    cat "${TMP_SOURCE_JSON_FILE}" | jq '.props.initialState.content.documents' | jq -r '.[].ingredientGroups['${group_index}'].fields.recipeIngredientItems[].fields|[.qty, .preText, .ingredient.fields.title, .postText] | @tsv' | \
      while IFS=$'\t' read -r qty unit item modifier; do
        ((ingredient_count++))
        [[ -n "${modifier}" ]] && [[ ${modifier} != ,* ]] && modifier=" ${modifier}"
        echo "        $([[ $ingredient_count -gt 1 ]] && echo ', ')\"$(echo "${qty} ${unit} ${item}${modifier}" | sed 's/\ \ */ /g')\""  >> ${TMP_RECIPE_JSON_FILE}
      done
    echo "      ]" >> "${TMP_RECIPE_JSON_FILE}"
    echo "    }" >> "${TMP_RECIPE_JSON_FILE}"
  done

  grouptitle=""
  if [[ $group_index -lt 0 ]]; then
    echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
    echo "      \"title\":\"${grouptitle}\"," >> "${TMP_RECIPE_JSON_FILE}"
    echo "      \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
    local ingredient_count=0
    cat "${TMP_SOURCE_JSON_FILE}" | jq '.props.initialState.content.documents' | jq -r '.[].ingredientGroups[].fields.recipeIngredientItems[].fields|[.qty, .preText, .ingredient.fields.title, .postText] | @tsv' | \
      while IFS=$'\t' read -r qty unit item modifier; do
        ((ingredient_count++))
        [[ -n "${modifier}" ]] && [[ ${modifier} != ,* ]] && modifier=" ${modifier}"
        echo "$([[ $ingredient_count -gt 1 ]] && echo ', ')\"$(echo "${qty} ${unit} ${item}${modifier}" | sed 's/\ \ */ /g')\""  >> ${TMP_RECIPE_JSON_FILE}
      done
    echo "      ]" >> "${TMP_RECIPE_JSON_FILE}"
    echo "    }" >> "${TMP_RECIPE_JSON_FILE}"
  fi
  echo "  ]," >> "${TMP_RECIPE_JSON_FILE}"
  unset \
    group_index \
    grouptitle \
    qty \
    unit \
    item \
    modifier \
    IFS

  # Directions
  echo "  \"direction_groups\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
  echo "      \"group\": \"\"" >> "${TMP_RECIPE_JSON_FILE}"
  echo "    , \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
  local direction_count=0
  for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\r/ /g' | sed 's/\\n/ /g' | jq --raw-output .props.initialState.content.documents | jq --raw-output .[].instructions[].fields.content); do
    ((direction_count++))
    echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
  echo "  ]," >> "${TMP_RECIPE_JSON_FILE}"
  unset \
    direction \
    direction_count \
    IFS

  local NOTES=""
  local NOTE_EXTRACT="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.props.initialState.content.documents' | jq -c '.[].headnote')"
  if [[ ${NOTE_EXTRACT} != null ]]; then
    NOTES="$(echo ${NOTE_EXTRACT} \
      | sed 's/\\r//g' \
      | sed 's/\\n/ /g' \
      | sed 's/<[^>]*>//g' \
      | sed 's/^"\(.*\)"$/\1/g' \
      | sed 's/"/\\"/g')"
  fi
  echo "  \"notes\": \"${NOTES}\"" >> "${TMP_RECIPE_JSON_FILE}"
  unset NOTES

  echo "}" >> "${TMP_RECIPE_JSON_FILE}"

  cat "${TMP_RECIPE_JSON_FILE}" | tr -d '\r' | jq --raw-output

  if [[ $FLAG_DEBUG -ne 0 ]]; then
    echo_debug "SOURCE_HTML_FILE    =${TMP_SOURCE_HTML_FILE}"
    echo_debug "SOURCE_JSON_FILE    =${TMP_SOURCE_JSON_FILE}"
    echo_debug "RECIPE_JSON_FILE    =${TMP_RECIPE_JSON_FILE}"
  else
    rm "${TMP_SOURCE_HTML_FILE}"
    rm "${TMP_SOURCE_JSON_FILE}"
    rm "${TMP_RECIPE_JSON_FILE}"
  fi

}

function saveur2json() {
  echo_debug "Building JSON from Saveur Page..."
  _URL=$1
  echo_debug "   _URL=${_URL}"

  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  local TMP_SOURCE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_data.json.XXXXXX)"
  local TMP_SOURCE_JSON_RAW_FILE="$(mktemp /tmp/${FUNCNAME[0]}_raw.json.XXXXXX)"
  local TMP_SOURCE_HTML_FILE="$(mktemp /tmp/${FUNCNAME[0]}.html.XXXXXX)"

  curl --compressed --silent $_URL | hxnormalize -x | tr -d '\r' | tr -d '\n' > ${TMP_SOURCE_HTML_FILE}

  cat "${TMP_RECIPE_JSON_FILE}" | tr -d '\r' | jq --raw-output

  echo "{" > "${TMP_RECIPE_JSON_FILE}"

  echo "  \"url\": \"$_URL\"," >> "${TMP_RECIPE_JSON_FILE}"

  TITLE="$(cat "${TMP_SOURCE_HTML_FILE}" | hxselect -c '.article_title' | sed 's/  */ /g')"
  DESCRIPTION="$(cat "${TMP_SOURCE_HTML_FILE}" | hxselect p.paragraph | sed 's/  */ /g' | hxselect -c p:first-child)"
  YIELD="$(cat "${TMP_SOURCE_HTML_FILE}" | hxselect -i -c 'div.yield span' | sed 's/  */ /g')"
  echo "  \"title\": \"$TITLE\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"description\": \"${DESCRIPTION}\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"yield\": \"${YIELD}\"," >> "${TMP_RECIPE_JSON_FILE}"

  # Parse Time
  PREP_MINUTES=0
  COOK_MINUTES=$(( $(rawtime2minutes $(cat "${TMP_SOURCE_HTML_FILE}" | hxselect -i -c div.cook-time 'meta::attr(content)')) ))
  TOTAL_MINUTES=$(( ${PREP_MINUTES} + ${COOK_MINUTES} ))
  if [[ $PREP_MINUTES -eq 0 ]] && [[ $TOTAL_MINUTES -gt 0 ]] && [[ $COOK_MINUTES -gt 0 ]]; then
    PREP_MINUTES=$(( ${TOTAL_MINUTES} - ${COOK_MINUTES} ))
  fi

  if [[ ${PREP_MINUTES} -gt 0 ]]; then
    echo "  \"preptime\": \"$(minutes2time ${PREP_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"
  else
    echo "  \"preptime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  fi

  if [[ ${COOK_MINUTES} -gt 0 ]]; then
    echo "  \"cooktime\": \"$(minutes2time ${COOK_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"
  else
    echo "  \"cooktime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  fi

  echo "  \"totaltime\": \"$(minutes2time ${TOTAL_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"

  AUTHOR="$(domain2publisher "$_URL")"
  echo "  \"author\": \"${AUTHOR}\"," >> "${TMP_RECIPE_JSON_FILE}"

  # Ingredient Groups and ingredients
  echo "  \"ingredient_groups\": [{" >> "${TMP_RECIPE_JSON_FILE}"
  # TODO: Figure out how to do grouping:
  #       Query: cat "${TMP_SOURCE_HTML_FILE}" | hxselect div.recipe | sed 's/  */ /g' | hxselect -i -c h2.part-title,ul
  echo "    \"title\":\"\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "    \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  local i_count=0
  for ingredient in $(cat "${TMP_SOURCE_HTML_FILE}" | hxselect -i -c -s '\n' 'li.ingredient' | sed -e's/  */ /g'); do
    ((i_count++))
    echo "        $([[ $i_count -gt 1 ]] && echo ', ')\"$(echo ${ingredient} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | tr -d '\r' | tr '\n' ' ' | sed 's/((/(/g' | sed 's/))/)/g' | sed 's/  */ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  unset ingredient
  unset i_count
  unset IFS
  echo "    ]" >> "${TMP_RECIPE_JSON_FILE}"
  echo "  }]," >> "${TMP_RECIPE_JSON_FILE}"

  echo "  \"direction_groups\": [{" >> "${TMP_RECIPE_JSON_FILE}"
  echo "    \"group\":\"\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "    \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  local i_count=0
  for ingredient in $(cat "${TMP_SOURCE_HTML_FILE}" | hxselect -i -c -s '\n' 'li.instruction' | sed -e's/  */ /g'); do
    ((i_count++))
    echo "        $([[ $i_count -gt 1 ]] && echo ', ')\"$(echo ${ingredient} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | tr -d '\r' | tr '\n' ' ' | sed 's/((/(/g' | sed 's/))/)/g' | sed 's/  */ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  unset ingredient
  unset i_count
  unset IFS
  echo "    ]" >> "${TMP_RECIPE_JSON_FILE}"
  echo "  }]" >> "${TMP_RECIPE_JSON_FILE}"

  #echo "  ,\"notes\": \"\"" >> "${TMP_RECIPE_JSON_FILE}"

  echo "}" >> "${TMP_RECIPE_JSON_FILE}"

  cat "${TMP_RECIPE_JSON_FILE}" | tr -d '\r' | jq --raw-output

  if [[ $FLAG_DEBUG -ne 0 ]]; then
    echo_debug "SOURCE_HTML_FILE    =${TMP_SOURCE_HTML_FILE}"
    echo_debug "SOURCE_JSON_RAW_FILE=${TMP_SOURCE_JSON_RAW_FILE}"
    echo_debug "SOURCE_JSON_FILE    =${TMP_SOURCE_JSON_FILE}"
    echo_debug "RECIPE_JSON_FILE    =${TMP_RECIPE_JSON_FILE}"
  else
    rm "${TMP_SOURCE_HTML_FILE}"
    rm "${TMP_SOURCE_JSON_RAW_FILE}"
    rm "${TMP_SOURCE_JSON_FILE}"
    rm "${TMP_RECIPE_JSON_FILE}"
  fi
}

function epicurious2json() {
  echo_debug "Building JSON from Epicurious Page..."
  _URL=$1
  echo_debug "   _URL=${_URL}"

  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  local TMP_SOURCE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_data.json.XXXXXX)"
  local TMP_SOURCE_JSON_RAW_FILE="$(mktemp /tmp/${FUNCNAME[0]}_raw.json.XXXXXX)"
  local TMP_SOURCE_HTML_FILE="$(mktemp /tmp/${FUNCNAME[0]}.html.XXXXXX)"

  curl --compressed --silent $_URL > ${TMP_SOURCE_HTML_FILE}

  cat ${TMP_SOURCE_HTML_FILE} \
    | hxnormalize -x 2>/dev/null \
    | hxselect -i -c "script" \
    | grep "root.__INITIAL_STATE__.store" \
    | sed 's/[^}]*$//' | sed 's/^[^{]*//' \
    | sed 's/"email":{"regExp":.*,"password"/"email":{"regExp":"","password"/g' \
    | sed 's/"password":{"regExp":.*,"messages"/"password":{"regExp":""},"messages"/g' \
    > ${TMP_SOURCE_JSON_RAW_FILE}

  cat "${TMP_SOURCE_JSON_RAW_FILE}" | jq --raw-output '.content' > "${TMP_SOURCE_JSON_FILE}"

  echo "{" > "${TMP_RECIPE_JSON_FILE}"

  echo "  \"url\": \"$_URL\"," >> "${TMP_RECIPE_JSON_FILE}"

  echo "  \"title\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .hed | sed 's/\"/\\\"/g')\"," >> "${TMP_RECIPE_JSON_FILE}"

  DESCRIPTION="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .dek | sed 's/\\r//g' | sed 's/\\n/ /g' | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | tr '\r' ' ' | tr '\n' ' ' | sed 's/\ \ //g' )"
  echo "  \"description\": \"${DESCRIPTION}\"," >> "${TMP_RECIPE_JSON_FILE}"

  local YIELD=$(cat ${TMP_SOURCE_JSON_FILE} | jq --compact-output '.servingSizeInfo.servingSizeDescription' 2>/dev/null | tr -d '\n'  | sed 's/\"//g')
  if [[ -z "${YIELD}" ]] || [[ $YIELD == null ]]; then
    YIELD=""
  fi
  echo "  \"yield\": \"${YIELD}\"," >> "${TMP_RECIPE_JSON_FILE}"

  # Parse Time
  PREP_MINUTES=$(( $(rawtime2minutes $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .formattedPrepTime)) ))
  COOK_MINUTES=$(( $(rawtime2minutes $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .formattedCookTime)) ))
  TOTAL_MINUTES=$(( ${PREP_MINUTES} + ${COOK_MINUTES} ))
  if [[ $PREP_MINUTES -eq 0 ]] && [[ $TOTAL_MINUTES -gt 0 ]] && [[ $COOK_MINUTES -gt 0 ]]; then
    PREP_MINUTES=$(( ${TOTAL_MINUTES} - ${COOK_MINUTES} ))
  fi

  if [[ ${PREP_MINUTES} -gt 0 ]]; then
    echo "  \"preptime\": \"$(minutes2time ${PREP_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"
  else
    echo "  \"preptime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  fi

  if [[ ${COOK_MINUTES} -gt 0 ]]; then
    echo "  \"cooktime\": \"$(minutes2time ${COOK_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"
  else
    echo "  \"cooktime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  fi

  echo "  \"totaltime\": \"$(minutes2time ${TOTAL_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"

  local PUBLISHER="Epicurious"
  local AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author[].name 2>/dev/null | sed 's/\"/\\\"/g')"
  if [[ -z "${AUTHOR}" ]] || [[  ${AUTHOR} == null ]]; then
    AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author.name 2>/dev/null | sed 's/\"/\\\"/g')"
    if [[ -z "${AUTHOR}" ]] || [[  ${AUTHOR} == null ]]; then
      AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author 2>/dev/null | sed 's/\"/\\\"/g')"
    fi
  fi
  if [[ -z "${AUTHOR}" ]] || [[ ${AUTHOR} == null ]] || [[ "${AUTHOR}" == "[]" ]] || [[ "${PUBLISHER}" == "${AUTHOR}" ]]; then
    AUTHOR="${PUBLISHER}"
  else
    AUTHOR="${PUBLISHER} (${AUTHOR})"
  fi
  echo "  \"author\": \"${AUTHOR}\"," >> "${TMP_RECIPE_JSON_FILE}"

  # Ingredient Groups and ingredients
  echo "  \"ingredient_groups\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.ingredientGroups[]' > /dev/null 2>&1
  ret_code=$?
  if [ ${ret_code} -eq 0 ]; then
    local ingredient_count=0
    local group_count=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.ingredientGroups | length')
    if [ ${group_count} -gt 1 ]; then
      group_idx=0

      while [ ${group_idx} -lt ${group_count} ]; do
        group=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.ingredientGroups['${group_idx}'].hed')
        echo "    $([[ $group_idx -gt 0 ]] && echo ','){" >> "${TMP_RECIPE_JSON_FILE}"
        echo "      \"title\": \"$(echo ${group} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
        echo "    , \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
        ingredient_count=0
        for ingredient in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .ingredientGroups[${group_idx}].ingredients[].description); do
          ((ingredient_count++))
          echo "    $([[ $ingredient_count -gt 1 ]] && echo ', ')\"$(echo ${ingredient} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
        done
        echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
        ((group_idx++))
      done
    else
      echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
      echo "      \"title\": \"\"" >> "${TMP_RECIPE_JSON_FILE}"
      echo "    , \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
      for ingredient in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .ingredientGroups[].ingredients[].description); do
        ((ingredient_count++))
        echo "    $([[ $ingredient_count -gt 1 ]] && echo ', ')\"$(echo ${ingredient} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
      done
      echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
    fi
  fi
  echo "    ]," >> "${TMP_RECIPE_JSON_FILE}"

  echo "  \"direction_groups\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.preparationGroups[]' > /dev/null 2>&1
  ret_code=$?
  if [ ${ret_code} -eq 0 ]; then
    local direction_count=0
    local group_count=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.preparationGroups | length')
    if [ ${group_count} -gt 1 ]; then
      group_idx=0

      while [ ${group_idx} -lt ${group_count} ]; do
        group=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.preparationGroups['${group_idx}'].hed')
        echo "    $([[ $group_idx -gt 0 ]] && echo ','){" >> "${TMP_RECIPE_JSON_FILE}"
        echo "      \"group\": \"$(echo ${group} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
        echo "    , \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
        direction_count=0
        for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .preparationGroups[${group_idx}].steps[].description); do
          ((direction_count++))
          echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
        done
        echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
        ((group_idx++))
      done
    else
      echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
      echo "      \"group\": \"\"" >> "${TMP_RECIPE_JSON_FILE}"
      echo "    , \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
      for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .preparationGroups[].steps[].description); do
        ((direction_count++))
        echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
      done
      echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
    fi
  fi

  echo "    ]" >> "${TMP_RECIPE_JSON_FILE}"
  unset direction
  unset direction_count
  unset IFS
  #TODO: Add .prepNotes


  echo "}" >> "${TMP_RECIPE_JSON_FILE}"

  cat "${TMP_RECIPE_JSON_FILE}" | tr -d '\r' | jq --raw-output

  if [[ $FLAG_DEBUG -ne 0 ]]; then
    echo_debug "SOURCE_HTML_FILE    =${TMP_SOURCE_HTML_FILE}"
    echo_debug "SOURCE_JSON_RAW_FILE=${TMP_SOURCE_JSON_RAW_FILE}"
    echo_debug "SOURCE_JSON_FILE    =${TMP_SOURCE_JSON_FILE}"
    echo_debug "RECIPE_JSON_FILE    =${TMP_RECIPE_JSON_FILE}"
  else
    rm "${TMP_SOURCE_HTML_FILE}"
    rm "${TMP_SOURCE_JSON_RAW_FILE}"
    rm "${TMP_SOURCE_JSON_FILE}"
    rm "${TMP_RECIPE_JSON_FILE}"
  fi
}

function generic2json() {
  echo_debug "Building JSON from Generic Page..."
  _URL=$1
  echo_debug "   _URL=${_URL}"

  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  local TMP_SOURCE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_data.json.XXXXXX)"
  local TMP_SOURCE_JSON_RAW_FILE="$(mktemp /tmp/${FUNCNAME[0]}_raw.json.XXXXXX)"
  local TMP_SOURCE_HTML_FILE="$(mktemp /tmp/${FUNCNAME[0]}.html.XXXXXX)"

  curl --compressed --silent $_URL > ${TMP_SOURCE_HTML_FILE}

  if grep --silent "<script[^>]*type=.application\/ld+json.[^>]*>" "${TMP_SOURCE_HTML_FILE}"; then
    echo_debug "Attempting to retrieve raw JSON using method 1"
    cat ${TMP_SOURCE_HTML_FILE} \
      | hxnormalize -x 2>/dev/null \
      | hxselect -i -c "script.yoast-schema-graph" \
      | sed 's/^[^\{]*//' \
      > ${TMP_SOURCE_JSON_RAW_FILE}

    recipetest="$(cat "${TMP_SOURCE_JSON_RAW_FILE}" | jq -c 'paths | select(.[-1] == "recipeIngredient")')"

    if [[ -z "${recipetest}" ]] || [[ ${recipetest} == null ]]; then
      echo_debug "Retrieve raw JSON using method 2"
      cat ${TMP_SOURCE_HTML_FILE} \
        | tr -d '\n' \
        | sed 's/.*<script[^>]*type=.application\/ld+json.[^>]*>//g' \
        | sed 's/<\/script>.*//g' \
        | sed 's/^[^\{]*//' \
        > ${TMP_SOURCE_JSON_RAW_FILE}
    fi

    echo_debug "Selecting Recipe JSON (Attempting Method 1: '.[]  | select(.\"@type\" == \"Recipe\")')"
    cat "${TMP_SOURCE_JSON_RAW_FILE}" | jq --raw-output '.[]  | select(."@type" == "Recipe")' 2>/dev/null > ${TMP_SOURCE_JSON_FILE}
    ret_code=$?
    if [ ${ret_code} -gt 0 ] || [ ! -s "${TMP_SOURCE_JSON_FILE}" ]; then
      echo_debug "Selecting Recipe JSON (Attempting Method 2: '.\"@graph\"[]  | select(.\"@type\" == \"Recipe\")')"
      cat "${TMP_SOURCE_JSON_RAW_FILE}" | jq --raw-output '."@graph"[]  | select(."@type" == "Recipe")' 2>/dev/null > ${TMP_SOURCE_JSON_FILE}
      ret_code=$?
      if [ ${ret_code} -gt 0 ] || [ ! -s "${TMP_SOURCE_JSON_FILE}" ]; then
        echo_debug "Selecting Recipe JSON (Attempting Method 3: '. | select(.\"@type\" == \"Recipe\")')"
        cat "${TMP_SOURCE_JSON_RAW_FILE}" | jq --raw-output '. | select(."@type" == "Recipe")' 2>/dev/null > ${TMP_SOURCE_JSON_FILE}
        ret_code=$?
        if [ ${ret_code} -gt 0 ] || [ ! -s "${TMP_SOURCE_JSON_FILE}" ]; then
          echo_debug "Copying over JSON (Attempting Method 4)"
          cat "${TMP_SOURCE_JSON_RAW_FILE}" | jq --raw-output 2>/dev/null > ${TMP_SOURCE_JSON_FILE}
        fi
      fi
    fi

    echo "{" > "${TMP_RECIPE_JSON_FILE}"

    echo "  \"url\": \"$_URL\"," >> "${TMP_RECIPE_JSON_FILE}"

    local TITLE=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .headline | sed 's/\"/\\\"/g')
    if [[ -z "${TITLE}" ]] || [[ ${TITLE} == null ]]; then
      TITLE=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .name 2>/dev/null | sed 's/\"/\\\"/g')
    fi
    echo "  \"title\": \"${TITLE}\"," >> "${TMP_RECIPE_JSON_FILE}"
    unset TITLE

    DESCRIPTION="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .description | sed 's/\\r//g' | sed 's/\\n/ /g' | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | tr '\r' ' ' | tr '\n' ' ' | sed 's/\ \ //g' | sed 's/^ *null *$//g' )"
    echo "  \"description\": \"${DESCRIPTION}\"," >> "${TMP_RECIPE_JSON_FILE}"

    local YIELD=$(echo $(cat ${TMP_SOURCE_JSON_FILE} | jq --compact-output '.recipeYield | max' 2>/dev/null || cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.recipeYield' 2>/dev/null ) | tr -d '\n'  | sed 's/\"//g')
    if [[ -z "${YIELD}" ]] || [[ $YIELD == null ]]; then
      YIELD=""
    fi
    echo "  \"yield\": \"${YIELD}\"," >> "${TMP_RECIPE_JSON_FILE}"

    # Parse Time
    TOTAL_MINUTES=$(( $(rawtime2minutes $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .totalTime)) ))
    COOK_MINUTES=$(( $(rawtime2minutes $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .cookTime)) ))
    PREP_MINUTES=$(( $(rawtime2minutes $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .prepTime)) ))
    if [[ $PREP_MINUTES -eq 0 ]] && [[ $TOTAL_MINUTES -gt 0 ]] && [[ $COOK_MINUTES -gt 0 ]]; then
      PREP_MINUTES=$(( ${TOTAL_MINUTES} - ${COOK_MINUTES} ))
    fi

    if [[ ${PREP_MINUTES} -gt 0 ]]; then
      echo "  \"preptime\": \"$(minutes2time ${PREP_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"
    else
      echo "  \"preptime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
    fi

    if [[ ${COOK_MINUTES} -gt 0 ]]; then
      echo "  \"cooktime\": \"$(minutes2time ${COOK_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"
    else
      echo "  \"cooktime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
    fi

    echo "  \"totaltime\": \"$(minutes2time ${TOTAL_MINUTES})\"," >> "${TMP_RECIPE_JSON_FILE}"

    local PUBLISHER=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.publisher.name'  2>/dev/null | sed 's/\"/\\\"/g')
    if [[ -z "${PUBLISHER}" ]] || [[ ${PUBLISHER} == null ]]; then
      PUBLISHER=$(cat "${TMP_SOURCE_JSON_RAW_FILE}" | jq '."@graph"[]? | select(."@type" == "Organization")? | .name?' 2>/dev/null | sed 's/\"//g' )
    fi
    if [[ -z "${PUBLISHER}" ]] || [[ ${PUBLISHER} == null ]]; then
      PUBLISHER="$(domain2publisher ${_URL})"
    fi
    local AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author[].name 2>/dev/null | sed 's/\"/\\\"/g')"
    if [[ -z "${AUTHOR}" ]] || [[  ${AUTHOR} == null ]]; then
      AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author.name 2>/dev/null | sed 's/\"/\\\"/g')"
      if [[ -z "${AUTHOR}" ]] || [[  ${AUTHOR} == null ]]; then
        AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author 2>/dev/null | sed 's/\"/\\\"/g')"
      fi
    fi
    if [[ -n "${PUBLISHER}" ]]; then
      if [[ -z "${AUTHOR}" ]] || [[  ${AUTHOR} == null ]] || [[ "${PUBLISHER}" == "${AUTHOR}" ]]; then
        AUTHOR="${PUBLISHER}"
      else
        if [[ "$AUTHOR" != *"$PUBLISHER"* ]]; then
          AUTHOR="${PUBLISHER} (${AUTHOR})"
        fi
      fi
    fi
    echo "  \"author\": \"${AUTHOR}\"," >> "${TMP_RECIPE_JSON_FILE}"

    # Ingredient Groups and ingredients
    echo "  \"ingredient_groups\": [{" >> "${TMP_RECIPE_JSON_FILE}"
    echo "    \"title\":\"\"," >> "${TMP_RECIPE_JSON_FILE}"
    echo "    \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
    IFS=$'\n'
    local i_count=0
    for ingredient in $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .recipeIngredient[]); do
      ((i_count++))
      echo "        $([[ $i_count -gt 1 ]] && echo ', ')\"$(echo ${ingredient} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | tr -d '\r' | tr '\n' ' ' | sed 's/((/(/g' | sed 's/))/)/g' | sed 's/  */ /g' | sed 's/[[:space:]]*$//' )\"" >> "${TMP_RECIPE_JSON_FILE}"
    done
    unset ingredient
    unset i_count
    unset IFS
    echo "    ]" >> "${TMP_RECIPE_JSON_FILE}"
    echo "  }]," >> "${TMP_RECIPE_JSON_FILE}"

    # Directions
    echo "  \"direction_groups\": [" >> "${TMP_RECIPE_JSON_FILE}"
    IFS=$'\n'
    cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .recipeInstructions[] > /dev/null 2>&1
    ret_code=$?
    if [ ${ret_code} -eq 0 ]; then
      local direction_count=0
      cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .recipeInstructions[].itemListElement[].text > /dev/null 2>&1
      ret_code=$?
      if [ ${ret_code} -eq 0 ]; then
        local group_count=0
        for group in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .recipeInstructions[].name); do
          echo "    $([[ $group_count -gt 0 ]] && echo ','){" >> "${TMP_RECIPE_JSON_FILE}"
          echo "      \"group\": \"$(echo ${group} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
          echo "    , \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
          direction_count=0
          for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .recipeInstructions[${group_count}].itemListElement[].text); do
            ((direction_count++))
            echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
          done
          echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
          ((group_count++))
        done
      else
        cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .recipeInstructions[].text > /dev/null 2>&1
        ret_code=$?
        if [ ${ret_code} -eq 0 ]; then
          echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
          echo "      \"group\": \"\"" >> "${TMP_RECIPE_JSON_FILE}"
          echo "    , \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
          for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .recipeInstructions[].text); do
            ((direction_count++))
            echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
          done
          echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
        else
          echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
          echo "      \"group\": \"\"" >> "${TMP_RECIPE_JSON_FILE}"
          echo "    , \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
          for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .recipeInstructions[]); do
            ((direction_count++))
            echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
          done
          echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
        fi
      fi
    else
      direction_count=1
      echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
      echo "      \"group\": \"\"" >> "${TMP_RECIPE_JSON_FILE}"
      echo "    , \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
      echo "    \"1. $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .recipeInstructions | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' | sed 's/\&nbsp\;/\ /g' | sed 's/\ \ /\ /g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
      echo "    ]}" >> "${TMP_RECIPE_JSON_FILE}"
    fi
    echo "    ]" >> "${TMP_RECIPE_JSON_FILE}"
    echo "}" >> "${TMP_RECIPE_JSON_FILE}"
    unset direction
    unset direction_count
    unset IFS
    cat "${TMP_RECIPE_JSON_FILE}" | tr -d '\r' | jq --raw-output
  else
    echo_error "ERROR: URL (${_URL}) not supported."
  fi

  if [[ $FLAG_DEBUG -ne 0 ]]; then
    echo_debug "SOURCE_HTML_FILE    =${TMP_SOURCE_HTML_FILE}"
    echo_debug "SOURCE_JSON_RAW_FILE=${TMP_SOURCE_JSON_RAW_FILE}"
    echo_debug "SOURCE_JSON_FILE    =${TMP_SOURCE_JSON_FILE}"
    echo_debug "RECIPE_JSON_FILE    =${TMP_RECIPE_JSON_FILE}"
  else
    rm "${TMP_SOURCE_HTML_FILE}"
    rm "${TMP_SOURCE_JSON_RAW_FILE}"
    rm "${TMP_SOURCE_JSON_FILE}"
    rm "${TMP_RECIPE_JSON_FILE}"
  fi
}

function recipe_json2rst() {
  echo_debug "Building reStructuredText from recipe JSON..."
  _JSON_FILE=$1
  echo_debug "   _JSON_FILE=${_JSON_FILE}"

  local TITLE=$(cat ${_JSON_FILE} | jq --raw-output .title)
  echo "$TITLE"
  echo "$TITLE" | sed 's/./=/g'
  echo ""

  local YIELD=$(cat ${_JSON_FILE} | jq --raw-output .yield)
  local PREPTIME=$(cat ${_JSON_FILE} | jq --raw-output .preptime)
  local COOKTIME=$(cat ${_JSON_FILE} | jq --raw-output .cooktime)
  local TOTAlTIME=$(cat ${_JSON_FILE} | jq --raw-output .totaltime)

  local INFO="| "
  [[ -n "${PREPTIME}" ]] && INFO="${INFO}Prep: ${PREPTIME} | "
  [[ -n "${TOTAlTIME}" ]] && INFO="${INFO}Total: ${TOTAlTIME} | "
  [[ -n "${YIELD}" ]] && INFO="${INFO}Yield: ${YIELD} |"
  INFO="${INFO%% }" # Remove Trailing space.
  if [[ ! "${INFO}" == "|" ]]; then
    echo "$INFO" | sed 's/[^|]/-/g' | sed 's/|/\+/g'
    echo "$INFO"
    echo "$INFO" | sed 's/[^|]/-/g' | sed 's/|/\+/g'
    echo ""
  fi

  local AUTHOR="$(cat ${_JSON_FILE} | jq --raw-output .author)"
  echo "Source: \`${AUTHOR} <${_URL}>\`__"
  echo ""

  local DESCRIPTION=$(cat ${_JSON_FILE} | jq --raw-output .description)
  if [[ $DESCRIPTION != null ]] && [[ -n "${DESCRIPTION}" ]]; then
    echo "$DESCRIPTION"  | fmt -w 75
    echo ""
  fi

  echo "Ingredients"
  echo "-----------"
  echo ""
  IFS=$'\n'
  local group_index=0
  local group_count=$(cat ${_JSON_FILE} | jq --raw-output '.ingredient_groups | length')
  while [[ $group_index -lt $group_count ]]; do
    grouptitle=$(cat ${_JSON_FILE} | jq --raw-output '.ingredient_groups['${group_index}'].title')
    if [[ ${grouptitle} != null ]] && [[ -n "${grouptitle}" ]]; then
      if [[ $group_index -gt 0 ]]; then
        echo
      fi
      echo "${grouptitle}"
      echo "${grouptitle}" | sed 's/./\^/g'
      echo
    fi
    for ingredient in $(cat ${_JSON_FILE} | jq --raw-output '.ingredient_groups['${group_index}'].ingredients[]'); do
      echo "- ${ingredient}"
    done
    ((group_index++))
    unset ingredient
  done
  unset grouptitle
  unset group_index
  unset IFS

  echo ""

  echo "Directions"
  echo "----------"
  echo ""
  IFS=$'\n'
  group_index=0
  for grouptitle_raw in $(cat ${_JSON_FILE} | jq '.direction_groups[].group'); do
    grouptitle=$(echo $grouptitle_raw | sed 's/\"//g')
    if [[ -n ${grouptitle} ]] || [[ "${grouptitle}" != "" ]]; then
      if [[ ${group_index} -gt 0 ]]; then
        echo ""
      fi
      echo "${grouptitle}"
      echo "${grouptitle}" | sed 's/./\^/g'
      echo ""
    fi
    local step=0
    for direction in $(cat ${_JSON_FILE} | jq --raw-output '.direction_groups['${group_index}'].directions[]'); do
      ((step++))
      i=0
      for line in $(echo ${direction} | sed 's/\*\*\*//g' | fmt -w 70); do
        ((i++))
        [[ $i -eq 1 ]] && echo -ne "$step. " || echo -ne "$(echo ${step}. | sed 's/./ /g') "
        echo "$line"
      done
      unset line
      unset i
    done
    ((group_index++))
  done
  unset direction
  unset step
  unset IFS

  if [[ $(cat ${_JSON_FILE} | jq --raw-output .notes) != null ]]; then
    echo
    echo "Notes"
    echo "-----"
    echo ""

    IFS=$'\n'
    for notes in $(cat ${_JSON_FILE} | jq --raw-output .notes); do
      i=0
      for line in $(echo ${notes} | sed 's/\*\*\*//g' | fmt -w 70); do
        ((i++))
        [[ $i -eq 1 ]] && echo -ne "* " || echo -ne "  "
        echo "$line"
      done
      unset line
      unset i
    done
    unset notes
    unset step
    unset IFS
  fi
  echo ""

  unset \
    AUTHOR \
    INFO \
    TOTAlTIME \
    YIELD \
    DESCRIPTION \
    TITLE \
    TMP_SOURCE_JSON_FILE
}

function recipe_json2md() {
  echo_debug "Building Markdown from recipe JSON..."
  _JSON_FILE=$1
  _HEADING_PREFIX=${2:-}
  echo_debug "   _JSON_FILE=${_JSON_FILE}"
  echo_debug "   _HEADING_PREFIX=${_HEADING_PREFIX}"

  local TITLE=$(cat ${_JSON_FILE} | jq --raw-output .title)
  echo "${_HEADING_PREFIX}# ${TITLE}"
  echo ""

  local YIELD=$(cat ${_JSON_FILE} | jq --raw-output .yield)
  #TODO: Handle Time better
  local TOTAlTIME=$(cat ${_JSON_FILE} | jq --raw-output .totaltime)
  local AUTHOR="$(cat ${_JSON_FILE} | jq --raw-output .author)"

  local INFO="| Time: $TOTAlTIME | Yield: $YIELD |"
  echo "$INFO" | sed 's/[^|]/-/g'
  echo "$INFO"
  echo "$INFO" | sed 's/[^|]/-/g'
  echo ""

  local SOURCE=$(echo "Source: [${AUTHOR}](${_URL})" | sed "s/\'/\`/g")
  echo "$SOURCE"
  echo ""

  local DESCRIPTION=$(cat ${_JSON_FILE} | jq --raw-output .description)
  if [[ $DESCRIPTION != null ]] && [[ -n "${DESCRIPTION}" ]]; then
    echo $DESCRIPTION  | fmt -w 75
    echo ""
  fi

  echo "${_HEADING_PREFIX}## Ingredients"
  echo ""
  IFS=$'\n'
  local group_index=0
  local group_count=$(cat ${_JSON_FILE} | jq --raw-output '.ingredient_groups | length')
  while [[ $group_index -lt $group_count ]]; do
    grouptitle=$(cat ${_JSON_FILE} | jq --raw-output '.ingredient_groups['${group_index}'].title')
    if [[ ${grouptitle} != null ]] && [[ -n "${grouptitle}" ]]; then
      echo
      echo "### ${grouptitle}"
    fi
    for ingredient in $(cat ${_JSON_FILE} | jq --raw-output '.ingredient_groups['${group_index}'].ingredients[]'); do
      echo "* ${ingredient}"
    done
    ((group_index++))
    unset ingredient
  done
  unset grouptitle
  unset group_index
  unset IFS

  echo ""

  echo "${_HEADING_PREFIX}## Directions"
  echo ""
  IFS=$'\n'
  group_index=0
  for grouptitle_raw in $(cat ${_JSON_FILE} | jq '.direction_groups[].group'); do
    grouptitle=$(echo ${grouptitle_raw} | sed 's/\"//g')
    if [[ -n ${grouptitle} ]] || [[ "${grouptitle}" != "" ]]; then
      if [[ ${group_index} -gt 0 ]]; then
        echo ""
      fi
      echo "### ${grouptitle}"
      echo ""
    fi
    local step=0
    for direction in $(cat ${_JSON_FILE} | jq --raw-output '.direction_groups['${group_index}'].directions[]'); do
      ((step++))
      i=0
      for line in $(echo "${direction}" | sed 's/\*\*\*//g' | fmt -w 70); do
        ((i++))
        [[ $i -eq 1 ]] && echo -ne "$step. " || echo -ne "$(echo ${step}. | sed 's/./ /g') "
        echo "$line"
      done
      unset line
      unset i
    done
    ((group_index++))
  done
  unset direction
  unset step
  unset IFS

  if [[ $(cat ${_JSON_FILE} | jq --raw-output .notes) != null ]]; then
    echo
    echo "${_HEADING_PREFIX}## Notes"
    echo ""

    IFS=$'\n'
    for notes in $(cat ${_JSON_FILE} | jq --raw-output .notes); do
      i=0
      for line in $(echo "${notes}" | sed 's/\*\*\*//g' | fmt -w 70); do
        ((i++))
        [[ $i -eq 1 ]] && echo -ne "* " || echo -ne "  "
        echo "$line"
      done
      unset line
      unset i
    done
    unset notes
    unset step
    unset IFS
  fi
  echo ""

  unset \
    AUTHOR \
    INFO \
    TOTAlTIME \
    YIELD \
    DESCRIPTION \
    TITLE \
    TMP_SOURCE_JSON_FILE
}

function output_filename() {
  _FILENAME=$1
  _EXT=$2

  if [[ -z "${_EXT}" ]]; then
    echo "${_FILENAME}"
  else
    echo "$(echo "${_FILENAME}.${_EXT}" | sed "s/\.${_EXT}\.${_EXT}/\.${_EXT}/g" )"
  fi
}

function recipe_output_file() {
  _JSON_FILE=$1
  _EXT=$2

  TEMP_OUT_FILE="/tmp/recipe.${_EXT}"

  TITLE="$(cat ${_JSON_FILE} | jq --raw-output .title)"

  case "${_EXT}" in
    json)
      [[ "${_JSON_FILE}" != "${TEMP_OUT_FILE}" ]] && cp "${_JSON_FILE}" "${TEMP_OUT_FILE}"
      ;;
    md)
      recipe_json2md "${_JSON_FILE}" > "${TEMP_OUT_FILE}"
      ;;
    rst)
      recipe_json2rst "${_JSON_FILE}" > "${TEMP_OUT_FILE}"
      ;;
    * )
      echo_error "ERROR: Unknown extention [${_EXT}]"
      exit ${EX_CANTCREAT}
  esac

  if [[ ${FLAG_SAVE_TO_FILE} -eq 1 ]]; then
    if [[ -z "${ARG_OUT_FiLE}" ]]; then
      SAVE_FILE="$(output_filename $(echo ${TITLE} | sed "s/[^a-zA-Z0-9]*//g") ${_EXT})"
    else
      SAVE_FILE="$(output_filename ${ARG_OUT_FiLE} ${_EXT})"
    fi
    echo_info "   Saving to ${SAVE_FILE}"
    cat "${TEMP_OUT_FILE}" > ${SAVE_FILE}
    unset SAVE_FILE
  else
    echo_info ""
    echo_info "$(head -c $(tput cols) < /dev/zero | tr '\0' '=')"
    echo_info ""
    cat "${TEMP_OUT_FILE}"
  fi

  unset TITLE
}

function recipe_output() {
  _JSON_FILE=$1
  echo_debug "   _JSON_FILE=${_JSON_FILE}"
  _JSON_FILE=$1

  TITLE="$(cat ${_JSON_FILE} | jq --raw-output .title)"
  if [[ -n "${TITLE}" ]]; then
    echo_info "   Processing complete: ${TITLE}"

    [[ ${FLAG_OUTPUT_JSON} -eq 1 ]] && recipe_output_file "${_JSON_FILE}" "json"
    [[ ${FLAG_OUTPUT_MD} -eq 1 ]] && recipe_output_file "${_JSON_FILE}" "md"
    [[ ${FLAG_OUTPUT_RST} -eq 1 ]] && recipe_output_file "${_JSON_FILE}" "rst"
  else
    echo_error "WARNING: Unable to retrieve title from json [${_JSON_FILE}]"
  fi

  unset TITLE
}

function main() {
  local TEMP_RECIPE_JSON_FILE="$(mktemp /tmp/recipe.json.XXXXXX)"

  parse_arguments "$@"

  check_requirements

  if [[ -z "${ARG_IN_FiLE}" ]]; then
    for URL in ${ARG_PASSED_URLS}; do
      echo_info "Processsing ${URL}..."

      # Branch based on domain
      DOMAIN=$(url2domain "${URL}")
      echo_debug "Branching based on domain (${DOMAIN})..."
      case "${DOMAIN}" in
        www.cooksillustrated.com|www.cookscountry.com|www.americatestkitchen.com)
          ci2json "${URL}" > "${TEMP_RECIPE_JSON_FILE}"
          ;;
        www.epicurious.com)
          epicurious2json "${URL}" > "${TEMP_RECIPE_JSON_FILE}"
          ;;
        www.saveur.com)
          saveur2json "${URL}" > "${TEMP_RECIPE_JSON_FILE}"
          ;;
        * )
          generic2json "${URL}" > "${TEMP_RECIPE_JSON_FILE}"
          #TODO: Add check for ld+json input.
          #echo_error "   ERROR: Unrecogniced domain [${DOMAIN}]"
          #exit ${EX_SOFTWARE}
      esac

      recipe_output "${TEMP_RECIPE_JSON_FILE}"
    done
  else
    echo_info "Processsing ${ARG_IN_FiLE}..."
    recipe_output "${ARG_IN_FiLE}"
  fi

  rm "${TEMP_RECIPE_JSON_FILE}" >/dev/null 2>&1

  unset \
    TEMP_RECIPE_JSON_FILE \
    TEMP_RST_FILE \
    URL
}

main "$@"
