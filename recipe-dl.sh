#!/bin/bash


# Exmple: recipe2rst.sh https://cooking.nytimes.com/recipes/1019530-cajun-shrimp-boil
# Exmple: recipe2rst.sh -s https://www.cooksillustrated.com/recipes/8800-sticky-buns


# Requires jq package
# Requires hxnormalize, hxselect, w3m
# brew install html-xml-utils

# Set temp files
TEMP_RECIPE_JSON_FILE="/tmp/recipe.json"
SCRIPT_NAME=$0

FLAG_SAVE_TO_FILE=0
FLAG_AUTHORIZE=0
FLAG_OUTPUT_JSON=0
FLAG_OUTPUT_MD=0
FLAG_OUTPUT_RST=0
PARAM_IN_FiLE=""
PARAM_OUT_FiLE=""
PASSED_URLS=""

function usage {
  echo "Usage: ${SCRIPT_NAME} [-ahjmros] [-f infile] [-o outfile] <URL> [<URL] ..."
  if [[ ! -z $1 ]]; then
    echo "  -a|--authorize         Force authorization of Cook Illustrated sites"
    echo "  -h|--help              Display help"
    echo "  -j|--output-json       Output results in JSON format"
    echo "  -m|--output-md         Output results in Markdown format"
    echo "  -r|--output-rst        Output results in reSTructuredText format"
    #echo "  -i|--infile infile     Specify input json file infile"
    echo "  -o|--outfile outfile   Specify output file outfile"
    echo "  -s|--save-to-file      Save output file(s)"
  fi
}

function parse_arguments () {
  while (( "$#" )); do
    case "$1" in
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
        PARAM_IN_FiLE=$1
        shift
        ;;
      -o|--outfile)
        FLAG_SAVE_TO_FILE=1
        shift
        PARAM_OUT_FiLE=$1
        shift
        ;;
      -a|--authorize)
        FLAG_AUTHORIZE=1
        shift
        ;;
      -h|--help)
        usage > $(tty)
        shift
        ;;
      -*|--*=) # unsupported flags
        echo "ERROR: Unsupported flag $1" >&2
        usage >&2
        exit 1
        ;;
      *) # preserve positional arguments
        PASSED_URLS="${PASSED_URLS} $1"
        shift
        ;;
    esac
  done

  FILETYPE_COUNT=0
  [[ ${FLAG_OUTPUT_JSON} -eq 1 ]] && ((FILETYPE_COUNT++))
  [[ ${FLAG_OUTPUT_MD} -eq 1 ]] && ((FILETYPE_COUNT++))
  [[ ${FLAG_OUTPUT_RST} -eq 1 ]] && ((FILETYPE_COUNT++))

  [[ ${FILETYPE_COUNT} -eq 0 ]] && FLAG_OUTPUT_RST=1
  if [[ ${FILETYPE_COUNT} -gt 1 ]] && [[ ${FLAG_SAVE_TO_FILE} -eq 0 ]]; then
    echo "INFO: More than one output file type select. Assuming 'Save to File'" > $(tty)
    FLAG_SAVE_TO_FILE=1
  fi

  # set positional arguments in their proper place
  eval set -- "$PARAMS"

  if [ -z "${PASSED_URLS}" ]; then
      usage "SHORT" >&2
      exit 1
  fi
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

function authorize_ci () {
  _COOKIE_FILE=$1
  _AUTH_DOMAIN=$2

  local NEXT_PAGE="$(rawurlencode $3)"

  echo "   Get authorization from ${_AUTH_DOMAIN}..." >$(tty)

  local TMP_HTML_FILE="$(mktemp /tmp/${FUNCNAME[0]}_signin.html.XXXXXX)"
  local TMP_POSTDATA="$(mktemp /tmp/${FUNCNAME[0]}_postdata.txt.XXXXXX)"

  curl --silent --cookie-jar ${_COOKIE_FILE} https://${_AUTH_DOMAIN}/sign_in?next=${NEXT_PAGE} | sed -n '/<form class="appForm" novalidate="novalidate" autocomplete="off" action="\/sessions"/,/<\/form>/p' > $TMP_HTML_FILE

  rm ${TMP_POSTDATA}
  IFS=$'\n'
  for input in $(cat $TMP_HTML_FILE | sed -e $'s/<input/\\\n<input/g' | grep '<input'); do
    echo -ne $(echo $input | sed -E 's/.* name=\"([^\"]*)\".* value=\"([^\"]*)\".*/\1=/g') >> ${TMP_POSTDATA}
    echo $(rawurlencode "$(echo $input | sed -E 's/.* name=\"([^\"]*)\".* value=\"([^\"]*)\".*/\2/g')") >> ${TMP_POSTDATA}
  done
  unset input
  unset IFS

  # Prompt for Username and password
  read -p "Enter email: " USER_EMAIL
  read -s -p "Enter Password: " USER_PASS

  local USER_EMAIL="$(rawurlencode ${USER_EMAIL})"
  local USER_PASS="$(rawurlencode ${USER_PASS})"

  sed -i -e 's/user\[email\]=/user\[email\]='${USER_EMAIL}'/g' ${TMP_POSTDATA}
  sed -i -e 's/user\[password\]=/user\[password\]='${USER_PASS}'/g' ${TMP_POSTDATA}

  echo "$(sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\&/g' ${TMP_POSTDATA})" > ${TMP_POSTDATA}

  curl --silent --list-only --data @${TMP_POSTDATA} --cookie-jar ${_COOKIE_FILE} --cookie ${_COOKIE_FILE} https://${_AUTH_DOMAIN}/sessions?next=${NEXT_PAGE} > /tmp/cisessions.html
}

function get_ci_page () {
  _URL=$1
  _HTML_FILE=$2

  local SCRIPT_PATH="`dirname \"${0}\"`"              # relative
  local SCRIPT_PATH="`( cd \"${SCRIPT_PATH}\" && pwd )`"  # absolutized and normalized
  if [ -z "${SCRIPT_PATH}" ] ; then
    # error; for some reason, the path is not accessible
    # to the script (e.g. permissions re-evaled after suid)
    SCRIPT_PATH="."
  fi

  local DOMAIN=$(echo "${_URL}" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
  local COOKIE_FILE="${SCRIPT_PATH}/${DOMAIN}.cookies"

  echo "   Using Cookie file: ${COOKIE_FILE}" >$(tty)
  [[ -f "${COOKIE_FILE}" ]] || FLAG_AUTHORIZE=1
  if [[ ${FLAG_AUTHORIZE} -eq 1 ]]; then
    authorize_ci "${COOKIE_FILE}" "${DOMAIN}" "${_URL}"
  fi
  curl --silent --cookie ${COOKIE_FILE} ${_URL} | hxnormalize -x > ${_HTML_FILE}
}

function ci2json() {
  _URL=$1

  local TMP_RECIPE_HTML_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.html.XXXXXX)"
  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  local TMP_SOURCE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_data.json.XXXXXX)"

  get_ci_page ${_URL} ${TMP_RECIPE_HTML_FILE}
  cat "${TMP_RECIPE_HTML_FILE}" | hxselect -i -c 'script#__NEXT_DATA__' > ${TMP_SOURCE_JSON_FILE} 2>/dev/null

  if [[ $? -ne 0 ]]; then
    if [[ ${FLAG_AUTHORIZE} -eq 0 ]]; then
      DOMAIN=$(echo "${_URL}" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
      COOKIE_FILE="${SCRIPT_PATH}/${DOMAIN}.cookies"
      authorize_ci "${COOKIE_FILE}" "${DOMAIN}" "${_URL}"
      get_ci_page ${_URL} ${TMP_RECIPE_HTML_FILE}
      cat "${TMP_RECIPE_HTML_FILE}" | hxselect -i -c 'script#__NEXT_DATA__' > ${TMP_SOURCE_JSON_FILE} 2>/dev/null
      [[ $? -ne 0 ]] && echo "   ERROR: Problem reading source." >&2 ; exit 403
    else
      FLAG_AUTHORIZE=0
      get_ci_page ${_URL} ${TMP_RECIPE_HTML_FILE}
      cat "${TMP_RECIPE_HTML_FILE}" | hxselect -i -c 'script#__NEXT_DATA__' > ${TMP_SOURCE_JSON_FILE} 2>/dev/null
      [[ $? -ne 0 ]] && echo "   ERROR: Problem reading source." >&2 ; exit 403
    fi
  fi
  rm "${TMP_RECIPE_HTML_FILE}"

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
    local DOMAIN=$(echo "${_URL}" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    case "${DOMAIN}" in
      www.americatestkitchen.com)
        AUTHOR="America's Test Kitchen"
        ;;
      www.cookscountry.com)
        AUTHOR="Cook's Country"
        ;;
      * )
        AUTHOR="Cook's Illustrated"
    esac
    unset DOMAIN
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
        [[ ! -z ${modifier} ]] && [[ ${modifier} != ,* ]] && modifier=" ${modifier}"
        echo "        $([[ $ingredient_count -gt 1 ]] && echo ', ')\"$(echo "${qty} ${unit} ${item}${modifier}" | sed 's/\ \ */ /g')\""  >> ${TMP_RECIPE_JSON_FILE}
      done
    echo "      ]" >> "${TMP_RECIPE_JSON_FILE}"
    echo "    }" >> "${TMP_RECIPE_JSON_FILE}"
  done
  unset grouptitle
  if [[ $group_index -lt 0 ]]; then
    echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
    echo "      \"title\":\"${grouptitle}\"," >> "${TMP_RECIPE_JSON_FILE}"
    echo "      \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
    local ingredient_count=0
    cat "${TMP_SOURCE_JSON_FILE}" | jq '.props.initialState.content.documents' | jq -r '.[].ingredientGroups[].fields.recipeIngredientItems[].fields|[.qty, .preText, .ingredient.fields.title, .postText] | @tsv' | \
      while IFS=$'\t' read -r qty unit item modifier; do
        ((ingredient_count++))
        [[ ! -z ${modifier} ]] && [[ ${modifier} != ,* ]] && modifier=" ${modifier}"
        echo "$([[ $ingredient_count -gt 1 ]] && echo ', ')\"$(echo "${qty} ${unit} ${item}${modifier}" | sed 's/\ \ */ /g')\""  >> ${TMP_RECIPE_JSON_FILE}
      done
    echo "      ]" >> "${TMP_RECIPE_JSON_FILE}"
    echo "    }" >> "${TMP_RECIPE_JSON_FILE}"
  fi
  echo "  ]," >> "${TMP_RECIPE_JSON_FILE}"
  unset group_index
  unset qty unit item modifier
  unset IFS

  # Directions
  echo "  \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  local direction_count=0
  for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\r/ /g' | sed 's/\\n/ /g' | jq --raw-output .props.initialState.content.documents | jq --raw-output .[].instructions[].fields.content); do
    ((direction_count++))
    echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  echo "  ]," >> "${TMP_RECIPE_JSON_FILE}"
  unset direction
  unset direction_count
  unset IFS

  local NOTES=""
  local NOTE_EXTRACT="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output '.props.initialState.content.documents' | jq -c '.[].headnote')"
  if [[ ${NOTE_EXTRACT} != null ]]; then
    NOTES="$(echo ${NOTE_EXTRACT} | sed 's/\\r//g' | sed 's/\\n/ /g' | sed 's/<[^>]*>//g' | sed 's/^\"\(.*\)\"$/\1/g' | sed 's/\"/\\\"/g')" >> "${TMP_RECIPE_JSON_FILE}"
  fi # | sed 's/^\\\"//g'
  echo "  \"notes\": \"${NOTES}\"" >> "${TMP_RECIPE_JSON_FILE}"
  unset NOTES

  echo "}" >> "${TMP_RECIPE_JSON_FILE}"

  rm "${TMP_SOURCE_JSON_FILE}"

  cat "${TMP_RECIPE_JSON_FILE}" | jq --raw-output && rm "${TMP_RECIPE_JSON_FILE}"
}

function nyt2json() {
  _URL=$1

  local TMP_SOURCE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"

  curl -s $_URL \
    | sed -n '/<script type="application\/ld+json">/,/<\/script>/p' \
    | sed '1d;$d' \
    > ${TMP_SOURCE_JSON_FILE}

  echo "{" > "${TMP_RECIPE_JSON_FILE}"

  echo "  \"url\": \"$_URL\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"title\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .name | sed 's/\"/\\\"/g')\"," >> "${TMP_RECIPE_JSON_FILE}"

  echo "  \"description\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .description | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g')\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"yield\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .recipeYield | sed 's/\"/\\\"/g')\"," >> "${TMP_RECIPE_JSON_FILE}"

  #TODO: Parse Time
  echo "  \"preptime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"cooktime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"totaltime\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .totalTime)\"," >> "${TMP_RECIPE_JSON_FILE}"

  PUBLISHER=$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .publisher.name  2>/dev/null | sed 's/\"/\\\"/g')
  if [[ -z ${PUBLISHER} ]] || [[ ${PUBLISHER} == null ]]; then
    PUBLISHER="New York Times"
  fi
  local AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author[].name 2>/dev/null | sed 's/\"/\\\"/g')"
  if [[ -z ${AUTHOR} ]] || [[  ${AUTHOR} == null ]]; then
    AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author.name | sed 's/\"/\\\"/g')"
  fi
  if [[ -z ${AUTHOR} ]] || [[  ${AUTHOR} == null ]]; then
    AUTHOR="${PUBLISHER}"
  else
    AUTHOR="${PUBLISHER} (${AUTHOR})"
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
    echo "        $([[ $i_count -gt 1 ]] && echo ', ')\"$(echo ${ingredient} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  unset ingredient
  unset i_count
  unset IFS
  echo "    ]" >> "${TMP_RECIPE_JSON_FILE}"
  echo "  }]," >> "${TMP_RECIPE_JSON_FILE}"

  # Directions
  echo "  \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  local direction_count=0
  for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .recipeInstructions[].text); do
    ((direction_count++))
    echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  echo "  ]" >> "${TMP_RECIPE_JSON_FILE}"
  echo "}" >> "${TMP_RECIPE_JSON_FILE}"
  unset direction
  unset direction_count
  unset IFS

  unset TMP_SOURCE_JSON_FILE

  cat "${TMP_RECIPE_JSON_FILE}" | jq --raw-output
}

function fn2json() {
  _URL=$1
  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  local TMP_SOURCE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_data.json.XXXXXX)"

  curl -s $_URL | grep 'application/ld+json' | sed 's/.*<script type="application\/ld+json">//g' | sed 's/<\/script>//g' |jq --raw-output '.[]  | select(."@type" == "Recipe")' > ${TMP_SOURCE_JSON_FILE}

  echo "{" > "${TMP_RECIPE_JSON_FILE}"

  echo "  \"url\": \"$_URL\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"title\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .headline | sed 's/\"/\\\"/g')\"," >> "${TMP_RECIPE_JSON_FILE}"

  echo "  \"description\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .description | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g')\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"yield\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .recipeYield)\"," >> "${TMP_RECIPE_JSON_FILE}"

  #TODO: Parse Time
  echo "  \"preptime\": \"\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"cooktime\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .cookTime)\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "  \"totaltime\": \"$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .totalTime)\"," >> "${TMP_RECIPE_JSON_FILE}"

  local AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author[].name 2>/dev/null | sed 's/\"/\\\"/g')"
  [[ -z ${AUTHOR} ]] && AUTHOR="$(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .author.name | sed 's/\"/\\\"/g')"
  echo "  \"author\": \"${AUTHOR}\"," >> "${TMP_RECIPE_JSON_FILE}"

  # Ingredient Groups and ingredients
  echo "  \"ingredient_groups\": [{" >> "${TMP_RECIPE_JSON_FILE}"
  echo "    \"title\":\"\"," >> "${TMP_RECIPE_JSON_FILE}"
  echo "    \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  local i_count=0
  for ingredient in $(cat ${TMP_SOURCE_JSON_FILE} | jq --raw-output .recipeIngredient[]); do
    ((i_count++))
    echo "        $([[ $i_count -gt 1 ]] && echo ', ')\"$(echo ${ingredient} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  unset ingredient
  unset i_count
  unset IFS
  echo "    ]" >> "${TMP_RECIPE_JSON_FILE}"
  echo "  }]," >> "${TMP_RECIPE_JSON_FILE}"

  # Directions
  echo "  \"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
  IFS=$'\n'
  local direction_count=0
  for direction in $(cat ${TMP_SOURCE_JSON_FILE} | sed 's/\\n/ /g'| jq --raw-output .recipeInstructions[].text); do
    ((direction_count++))
    echo "    $([[ $direction_count -gt 1 ]] && echo ', ')\"$(echo ${direction} | sed 's/<[^>]*>//g' | sed 's/\"/\\\"/g' )\"" >> "${TMP_RECIPE_JSON_FILE}"
  done
  echo "  ]" >> "${TMP_RECIPE_JSON_FILE}"
  echo "}" >> "${TMP_RECIPE_JSON_FILE}"
  unset direction
  unset direction_count
  unset IFS

  rm "${TMP_SOURCE_JSON_FILE}"

  cat "${TMP_RECIPE_JSON_FILE}" | jq --raw-output
  rm "${TMP_RECIPE_JSON_FILE}"
}

function recipe_json2rst() {
  _JSON_FILE=$1

  local TITLE=$(cat ${_JSON_FILE} | jq --raw-output .title)
  echo "$TITLE"
  echo "$TITLE" | sed 's/./=/g'
  echo ""

  local YIELD=$(cat ${_JSON_FILE} | jq --raw-output .yield)
  #TODO: Handle Time better
  local TOTAlTIME=$(cat ${_JSON_FILE} | jq --raw-output .totaltime)
  local AUTHOR="$(cat ${_JSON_FILE} | jq --raw-output .author)"

  local INFO="| Time: $TOTAlTIME | Yield: $YIELD |"
  echo "$INFO" | sed 's/[^|]/-/g' | sed 's/\|/\+/g'
  echo "$INFO"
  echo "$INFO" | sed 's/[^|]/-/g' | sed 's/\|/\+/g'
  echo ""

  local SOURCE=$(echo "Source: '${AUTHOR} <${_URL}>'__" | sed "s/\'/\`/g")
  echo "$SOURCE"
  echo ""

  local DESCRIPTION=$(cat ${_JSON_FILE} | jq --raw-output .description)
  if [[ $DESCRIPTION != null ]] && [[ ! -z ${DESCRIPTION} ]]; then
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
    if [[ ${grouptitle} != null ]] && [[ ! -z ${grouptitle} ]]; then
      echo
      echo "${grouptitle}"
      echo "${grouptitle}" | sed 's/./\^/g'
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
  local step=0
  for direction in $(cat ${_JSON_FILE} | jq --raw-output '.directions[]'); do
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

  unset AUTHOR
  unset INFO
  unset TOTAlTIME
  unset YIELD
  unset DESCRIPTION
  unset TITLE

  unset TMP_SOURCE_JSON_FILE
}

function recipe_json2md() {
  _JSON_FILE=$1
  _HEADING_PREFIX=$2

  local TITLE=$(cat ${_JSON_FILE} | jq --raw-output .title)
  echo "${_HEADING_PREFIX}#${TITLE}"
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
  if [[ $DESCRIPTION != null ]] && [[ ! -z ${DESCRIPTION} ]]; then
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
    if [[ ${grouptitle} != null ]] && [[ ! -z ${grouptitle} ]]; then
      echo
      echo "${grouptitle}"
      echo "${grouptitle}" | sed 's/./\^/g'
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
  local step=0
  for direction in $(cat ${_JSON_FILE} | jq --raw-output .directions[]); do
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

  unset AUTHOR
  unset INFO
  unset TOTAlTIME
  unset YIELD
  unset DESCRIPTION
  unset TITLE

  unset TMP_SOURCE_JSON_FILE
}

function output_filename() {
  _FILENAME=$1
  _EXT=$2

  if [[ -z ${EXT} ]]; then
    echo "${_FILENAME}"
  else
    echo "$(echo "${_FILENAME}.${_EXT}" | sed "s/\.${EXT}\.${EXT}/\.${EXT}/g" )"
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
      echo "ERROR: Unknown extention [${_EXT}]"
      exit 405
  esac

  if [[ ${FLAG_SAVE_TO_FILE} -eq 1 ]]; then
    if [[ -z ${PARAM_OUT_FiLE} ]]; then
      SAVE_FILE="$(output_filename $(echo ${TITLE} | sed "s/[^a-zA-Z0-9]*//g") ${_EXT})"
    else
      SAVE_FILE="$(output_filename ${PARAM_OUT_FiLE} ${_EXT})"
    fi
    echo "   Saving to ${SAVE_FILE}"
    cat "${TEMP_OUT_FILE}" > ${SAVE_FILE}
    unset SAVE_FILE
  else
    cat "${TEMP_OUT_FILE}"
  fi

  unset TITLE
}

function time2minutes() {
  _TIME=$1

  local HOUR=$(( $(echo "${_TIME}" | sed 's/^P.*T\([0-9]*\)H.*/\1/g') ))
  local MINUTES=$(( $(echo "${_TIME}" | sed 's/^P.*H\([0-9]*\)M.*/\1/g') ))

  TOTAL_MINUTES=$((${HOUR}*60+${MINUTES}))
  echo $TOTAL_MINUTES
}

#TODO
function minues2time() {
  _MINUTES=$1

  local HOUR=$(( $(echo "${_TIME}" | sed 's/^P.*T\([0-9]*\)H.*/\1/g') ))
  local MINUTES=$(( $(echo "${_TIME}" | sed 's/^P.*H\([0-9]*\)M.*/\1/g') ))

  TIME=$((${HOUR}*60+${MINUTES}))
  echo "$TIME"
}

function recipe_output() {
  _JSON_FILE=$1

  TITLE="$(cat ${_JSON_FILE} | jq --raw-output .title)"
  if [[ ! -z ${TITLE} ]]; then
    echo "   Processing complete: ${TITLE}" >$(tty)

    [[ ${FLAG_OUTPUT_JSON} -eq 1 ]] && recipe_output_file "${_JSON_FILE}" "json"
    [[ ${FLAG_OUTPUT_MD} -eq 1 ]] && recipe_output_file "${_JSON_FILE}" "md"
    [[ ${FLAG_OUTPUT_RST} -eq 1 ]] && recipe_output_file "${_JSON_FILE}" "rst"
  else
    echo "WARNING: Unable to retrieve title from json [${_JSON_FILE}]" >&2
  fi
  unset TITLE
}

parse_arguments "$@"
# TODO: Check for required items.
# TODO: System check

if [[ -z ${PARAM_IN_FiLE} ]]; then
  for URL in ${PASSED_URLS}; do
    echo "Processsing ${URL}..." >$(tty)

    # Branch based on domain
    DOMAIN=$(echo "${URL}" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    case "${DOMAIN}" in
      www.cooksillustrated.com|www.cookscountry.com|www.americatestkitchen.com)
        ci2json "${URL}" > "${TEMP_RECIPE_JSON_FILE}"
        ;;
      cooking.nytimes.com|www.bonappetit.com)
        nyt2json "${URL}" > "${TEMP_RECIPE_JSON_FILE}"
        ;;
      www.foodnetwork.com|www.cookingchanneltv.com)
        fn2json "${URL}" > "${TEMP_RECIPE_JSON_FILE}"
        ;;
      * )
        echo "   ERROR: Unrecogniced domain [${DOMAIN}]" >&2
        exit 404
    esac

    recipe_output "${TEMP_RECIPE_JSON_FILE}"
  done
else
  recipe_output "${PARAM_IN_FiLE}"
fi

unset TEMP_RST_FILE
unset URL
