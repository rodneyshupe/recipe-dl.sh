#!/bin/bash
set -eu

#TODO: Add author/source
#TODO: Yield
#TODO: Time
#TODO: Description
#TODO: Notes
#TODO: Variations

SCRIPT_NAME=$0

# EXIT CODES
EX_OK=0            # successful termination
EX_USAGE=64        # command line usage error
EX_DATAERR=65      # data format error
EX_NOINPUT=66      # cannot open input
# EX_NOUSER=67       # addressee unknown
# EX_NOHOST=68       # host name unknown
# EX_UNAVAILABLE=69  # service unavailable
EX_SOFTWARE=70     # internal software error
# EX_OSERR=71        # system error (e.g., can't fork)
EX_OSFILE=72       # critical OS file missing
EX_CANTCREAT=73    # can't create (user) output file
# EX_IOERR=74        # input/output error
# EX_TEMPFAIL=75     # temp failure; user is invited to retry
# EX_PROTOCOL=76     # remote error in protocol
EX_NOPERM=77       # permission denied
# EX_CONFIG=78       # configuration error

FLAG_DEBUG=0
ARG_IN_FiLE=""
ARG_OUT_FiLE=""
ARG_RECIPE_NAME=""

function usage {
  echo "Usage: ${SCRIPT_NAME} [-h] [-i infile] [-o outfile] <URL> [<URL] ..."
  if [[ ! -z ${1:-} ]]; then
    #echo "  -d|--debug             Debug"
    echo "  -h|--help              Display help"
    echo "  -i|--infile infile     Specify input json file infile"
    echo "  -o|--outfile outfile   Specify output file outfile"
  fi
}

function parse_arguments () {
  while (( "$#" )); do
    case "$1" in
      -d|--debug)
        FLAG_DEBUG=1
        shift
        ;;
      -r|--recipe)
        shift
        ARG_RECIPE_NAME=$1
        shift
        ;;
      -i|--infile)
        shift
        ARG_IN_FiLE=$1
        shift
        ;;
      -o|--outfile)
        shift
        ARG_OUT_FiLE=$1
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
        echo_error "ERROR: Unsupported argument $1"
        echo_error "$(usage)"
        exit ${EX_USAGE}
        ;;
    esac
  done
}

function command_exists() {
  command -v "$@" > /dev/null 2>&1
}

function echo_info() {
  echo "$@" >$(tty)
}

function echo_debug() {
  if [[ $FLAG_DEBUG -eq 1 ]]; then
    echo_info "${SCRIPT_NAME} DEBUG: $@"
  fi
}

function echo_error() {
  echo "$@" >&2
}

function rst2json() {
  IFS=

  FLAG_INGREDIENT_LIST_OPEN=0
  FLAG_INGREDIENT_GROUP_OPEN=0
  FLAG_INGREDIENT_GROUPS_OPEN=0
  FLAG_DIRECTION_OPEN=0
  FLAG_RECIPE_OPEN=0

  function close_recipe() {
    close_section
    if [[ ${FLAG_RECIPE_OPEN} -eq 1 ]]; then
      echo "}" >> "${TMP_RECIPE_JSON_FILE}"
      FLAG_RECIPE_OPEN=0
    fi
  }
  function close_section() {
    close_subsection
    if [[ ${FLAG_INGREDIENT_GROUPS_OPEN} -eq 1 ]]; then
      echo "  ]" >> "${TMP_RECIPE_JSON_FILE}"
      FLAG_INGREDIENT_GROUPS_OPEN=0
    fi
    if [[ ${FLAG_DIRECTION_OPEN} -eq 1 ]]; then
      if [[ ${DIRECTION_LINE_OPEN} -eq 1 ]]; then
        echo -ne "\"\n" >> ${TMP_RECIPE_JSON_FILE}
        DIRECTION_LINE_OPEN=0
      fi
      echo "  ]" >> "${TMP_RECIPE_JSON_FILE}"
      FLAG_DIRECTION_OPEN=0
    fi
  }
  function close_subsection(){
    if [[ $FLAG_INGREDIENT_LIST_OPEN -eq 1 ]]; then
      echo "      ]" >> "${TMP_RECIPE_JSON_FILE}"
      FLAG_INGREDIENT_LIST_OPEN=0
    fi
    if [[ $FLAG_INGREDIENT_GROUP_OPEN -eq 1 ]]; then
      echo "    }" >> "${TMP_RECIPE_JSON_FILE}"
      FLAG_INGREDIENT_GROUP_OPEN=0
    fi
  }

  INPUT_FILE="${1:-/dev/stdin}"
  echo_debug "Input file [${INPUT_FILE}]"

  # Create new file handle 5
  exec 5< "${INPUT_FILE}" # Now you can use "<&5" to read from this file


  local TMP_RECIPE_JSON_FILE="$(mktemp /tmp/${FUNCNAME[0]}_recipe.json.XXXXXX)"
  echo_debug "Temporary JSON file=${TMP_RECIPE_JSON_FILE}"

  echo "[" > "${TMP_RECIPE_JSON_FILE}"

  CATEGORY=""
  CURRENT_SECTION=""
  TITLE=""
  HEADER_CONTENT=""
  RECIPE_COUNT=0

  read line1 <&5
  line1_trimmed="$(echo "${line1}" | sed 's/^\ *//g' | sed 's/\ *$//g')"
  while read line2 <&5 ; do
    line2_trimmed="$(echo "${line2}" | sed 's/^\ *//g' | sed 's/\ *$//g')"

    if [[ ! -z ${line2_trimmed} ]] && [[ "${line2_trimmed}" == "$(echo "$line2_trimmed" | sed "s/./${line2_trimmed:0:1}/g")" ]]; then
      case "${line2_trimmed:0:1}" in
        '=')
          (( RECIPE_COUNT++ ))
          RECIPE_TITLE="${line1}"
          close_recipe
          if [[ $RECIPE_COUNT -gt 1 ]]; then
            echo "," >> "${TMP_RECIPE_JSON_FILE}"
          fi

          echo_debug "Recipe: ${RECIPE_TITLE}"
          echo "{" >> "${TMP_RECIPE_JSON_FILE}"
          FLAG_RECIPE_OPEN=1
          if [[ ! -z ${CATEGORY} ]] && [[ "${CATEGORY}" != "" ]]; then
            echo "  \"@category\": \"${CATEGORY}\"," >> "${TMP_RECIPE_JSON_FILE}"
          fi
          echo "  \"title\": \"${RECIPE_TITLE}\"" >> "${TMP_RECIPE_JSON_FILE}"
          CURRENT_SECTION="header"
          CURRENT_SUBSECTION=""
          HEADER_CONTENT=""

          #read line2 <&5
          #line1="${line2}"
          #line1_trimmed="$(echo "${line1}" | sed 's/^\ *//g' | sed 's/\ *$//g')"
          ;;
        '-')
          NEW_SECTION="$(echo "${line1_trimmed}" | tr '[:upper:]' '[:lower:]')"
          CURRENT_SUBSECTION=""
          case "${CURRENT_SECTION}" in
            "header")
              echo ",\"@HEADER_BLOCK\": \"${HEADER_CONTENT}\"" >> "${TMP_RECIPE_JSON_FILE}"
              URL=""
              #echo "${HEADER_CONTENT}" | sed 's/^[^\<]*\<\([^\>]\)\>.*$/\1/g' &&
              URL=$(echo ${HEADER_CONTENT} | tr '\\\n' '\n' | sed 's/^n//g' | grep '.*Source.*\`.*[^\<]*\<\([^\>]\)\>.*\`__.*') | sed 's/.*\`.*[^\<]*\<\([^\>]\)\>.*\`__.*/\1/g'
              if [ ! -z $URL ]; then
                echo_debug "URL=$URL"
              fi
              close_section
              ;;
            "ingredients"|"directions")
              close_section
              ;;
            "notes")
              close_section
              ;;
            "variations")
              close_section
              ;;
          esac
          case "${NEW_SECTION}" in
            "header")
              ;;
            "ingredients")
              echo "  ,\"ingredient_groups\": [" >> "${TMP_RECIPE_JSON_FILE}"
              FLAG_INGREDIENT_GROUPS_OPEN=1
              FLAG_INGREDIENT_GROUP_OPEN=0
              FLAG_INGREDIENT_LIST_OPEN=0
              GROUP_COUNT=0
              line1="${line2}"
              line1_trimmed="$(echo "${line1}" | sed 's/^\ *//g' | sed 's/\ *$//g')"
              read line2 <&5
              ;;
            "directions")
              echo "  ,\"directions\": [" >> "${TMP_RECIPE_JSON_FILE}"
              DIRECTION_COUNT=0
              DIRECTION_LINE_OPEN=0
              DIRECTION=""
              FLAG_DIRECTION_OPEN=1
              ;;
            "notes")
              ;;
            "variations")
              ;;
          esac

          CURRENT_SECTION=${NEW_SECTION}
          ;;
        '^')

          NEW_SUBSECTION="$(echo "${line1_trimmed}" | tr '[:upper:]' '[:lower:]')"
          if ! [[ "${NEW_SUBSECTION}" == "${CURRENT_SUBSECTION}" ]]; then
            if [[ "${CURRENT_SECTION}" == "ingredients" ]]; then
              close_subsection
              (( GROUP_COUNT++ ))
              [[ $GROUP_COUNT -gt 1 ]] && echo "," >> "${TMP_RECIPE_JSON_FILE}"
              echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
              echo "      \"title\":\"${NEW_SUBSECTION}\"," >> "${TMP_RECIPE_JSON_FILE}"
              echo "      \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
              FLAG_INGREDIENT_GROUP_OPEN=1
              FLAG_INGREDIENT_LIST_OPEN=1
              INGREDIENT_COUNT=0

              line1="${line2}"
              line1_trimmed="$(echo "${line1}" | sed 's/^\ *//g' | sed 's/\ *$//g')"
              read line2 <&5
            fi
            CURRENT_SUBSECTION="${NEW_SUBSECTION}"
          fi
          ;;
        '*')
          if [[ ! -z "$line1_trimmed" ]]; then
            CATEGORY="$line1_trimmed"
            echo_debug "Category: ${CATEGORY}"
          fi
          ;;
        *)
          echo_error "ERROR: UNKNOWN DELIMITER LINE:[${line1}][${line2}]"
          exit 1
      esac
    else
      #echo_debug "Current Section: ${CURRENT_SECTION}"
      case "${CURRENT_SECTION}" in
        "header")
          if [[ "${line1_trimmed:0:3}" != "===" ]] && [[ ! -z ${line1_trimmed} ]] && [[ "${line1_trimmed}" != "" ]]; then
            HEADER_CONTENT="${HEADER_CONTENT}${line1}\n"
          fi
          ;;
        "ingredients")
          if [[ "${line1_trimmed:0:2}" == "- " ]]; then
            if [[ $FLAG_INGREDIENT_GROUP_OPEN -ne 1 ]]; then
              close_subsection
              (( GROUP_COUNT++ ))
              [[ $GROUP_COUNT -gt 1 ]] && echo "," >> "${TMP_RECIPE_JSON_FILE}"
              echo "    {" >> "${TMP_RECIPE_JSON_FILE}"
              echo "      \"title\":\"\"," >> "${TMP_RECIPE_JSON_FILE}"
              echo "      \"ingredients\": [" >> "${TMP_RECIPE_JSON_FILE}"
              FLAG_INGREDIENT_LIST_OPEN=1
              FLAG_INGREDIENT_GROUP_OPEN=1
              INGREDIENT_COUNT=0
              FLAG_GROUP_TITLE=1
            fi
            (( INGREDIENT_COUNT++ ))
            echo -ne "$([[ $INGREDIENT_COUNT -gt 1 ]] && echo ', ')\"$(echo "${line1_trimmed}" | sed 's/^\-\ *//g' | sed 's/\ \ */ /g')" >> ${TMP_RECIPE_JSON_FILE}
            if [[ "${line2_trimmed:0:2}" == "- " ]] || [[ -z ${line2_trimmed} ]]; then
              echo "\"" >> ${TMP_RECIPE_JSON_FILE}
            else
              echo -ne " " >> ${TMP_RECIPE_JSON_FILE}
            fi
          else
            if [[ "${line1_trimmed:0:3}" != "---" ]] && [[ "${line1_trimmed:0:3}" != "^^^" ]]; then
              echo -ne "$(echo "${line1_trimmed}" | sed 's/\ \ */ /g')" >> ${TMP_RECIPE_JSON_FILE}
              if [[ "${line2_trimmed:0:2}" == "- " ]] \
                || [[ -z ${line2_trimmed} ]] \
                || [[ "${line2_trimmed}" == "" ]]; then
                echo "\"" >> ${TMP_RECIPE_JSON_FILE}
              else
                echo -ne " " >> ${TMP_RECIPE_JSON_FILE}
              fi
            fi
          fi
          ;;
        "directions")
          if [[ ! -z ${line1_trimmed} ]] \
            && [[ "${line1_trimmed:0:3}" != '---' ]] \
            && [[ "${line1_trimmed:0:3}" != '^^^' ]] \
            && [[ "${line1_trimmed:0:3}" != '.. ' ]] \
            && [[ "${line1_trimmed}" != '<p style="page-break-before: always"/>' ]] \
            && [[ "${line1_trimmed}" != 'PageBreak recipePage' ]]; then
            (( DIRECTION_COUNT++ ))

            [[ ${DIRECTION_LINE_OPEN} -eq 0 ]] && line1_trimmed="$(echo "${line1_trimmed}" | sed 's/^[0-9\#]*\.\ *//g')"

            echo -ne "$([[ $DIRECTION_COUNT -gt 1 ]] && [[ ${DIRECTION_LINE_OPEN} -eq 0 ]] && echo -ne ', ')$([[ ${DIRECTION_LINE_OPEN} -eq 0 ]] && echo -ne "\"")$(echo -ne "${line1_trimmed}" | sed 's/\ \ */ /g')" >> ${TMP_RECIPE_JSON_FILE}
            DIRECTION_LINE_OPEN=1
            if [[ "${line2:0:3}" != "   " ]] || [[ -z "${line2_trimmed}" ]]; then
              echo -ne "\"\n" >> ${TMP_RECIPE_JSON_FILE}
              DIRECTION_LINE_OPEN=0
            else
              echo -ne " " >> ${TMP_RECIPE_JSON_FILE}
            fi
          fi
          ;;
        "notes")
          ;;
      esac
    fi

    line1="$line2"
    line1_trimmed="${line2_trimmed}"
  done


  # Close file handle 5
  exec 5<&-
  close_section

  close_recipe
  echo "]" >> "${TMP_RECIPE_JSON_FILE}"
  unset IFS

  if [[ -z ${ARG_RECIPE_NAME} ]] || [[ "${ARG_RECIPE_NAME}" == "" ]]; then
    cat "${TMP_RECIPE_JSON_FILE}" | jq
  else
    echo_error "Looking for recipe: [${ARG_RECIPE_NAME}]"
    cat "${TMP_RECIPE_JSON_FILE}" | jq ".[] | select(\".title\"==\"${ARG_RECIPE_NAME}\")"
  fi
}

parse_arguments $@
echo_debug "Processing ${ARG_IN_FiLE}"
rst2json "$ARG_IN_FiLE"
