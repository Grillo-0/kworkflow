# NOTE: src/kw_config_loader.sh must be included before this file
include "$KW_LIB_DIR/kw_string.sh"

# Array with compression programs accepted by tar
declare -ga compression_programs=('gzip' 'bzip2' 'lzip' 'lzma' 'lzop' 'zstd'
  'xz' 'auto-compress')

# A common task used inside kw is a string separation based on a delimiter, for
# this reason, this function tries to handle this scenario by getting a
# delimiter character followed by the position that the users want to retrieve.
# For example:
# In the kw code, we use the pattern "<STRING1>:<STRING2>" for handling IP and
# port, we can use get_based_on_delimiter() helper to handle the ':' delimiter
# and based on the positional value the user can get the <STRING1> or
# <STRING2>.
#
# @string: String formated as <STRING1>:<STRING2>
# @delimiter: A delimiter character
# @position: The string position we want after @delimiter
#
# Returns:
# Return a "string" corresponding to the position number and a code value that
# specify the result (useful for checking if something went wrong). In case of
# error, "string" is displayed in the printf command and EINVAL code is
# returned.Probably, you want to execute this function is a subshell and save
# the output in a variable.
function get_based_on_delimiter()
{
  local string="$1"
  local delimiter="$2"
  local position="$3"
  local output=''
  local ret=0

  delimiter=${delimiter:-':'}

  output=$(printf '%s\n' "$string" | grep -i "$delimiter")
  if [[ "$?" != 0 ]]; then
    printf '%s\n' "$string"
    return 22 # EINVAL
  fi

  output=$(printf '%s\n' "$string" | cut -d "$delimiter" -f"$position")
  if [[ -z "$output" ]]; then
    output="$string"
    ret=22 # EINVAL
  fi
  printf '%s\n' "$output"
  return "$ret"
}

# This function executes any command and provides a mechanism to display the
# command in the terminal. Additionally, there's a test mode which only
# displays the commands, and it is useful for implementing unit tests.
#
# @flag: Expecting a flag, that could be SILENT, COMPLAIN, WARNING, SUCCESS,
#        TEST_MODE, and HIGHLIGHT_CMD. By default, cmd_manager does not expects
#        flags and always show the command.
# @@: Target command.
# @redirect_mode: If set to KW_REDIRECT_MODE, it will read output_path.
# @output_path: We expect a path to save the file's command output
#
# Returns:
# Return the exit status of the command defined by the string or 0 in the case
# of TEST_MODE
function cmd_manager()
{
  local flag="$1"
  shift 1 # Let's remove flag parameter
  local command_for_eval_array=("$@")
  local redirect_mode="${*: -2:1}" # Last but one
  local output_path="${*: -1}"     # Last
  local command_for_eval=''
  local base_path

  if [[ "$redirect_mode" == 'KW_REDIRECT_MODE' ]]; then
    base_path="${output_path%/*}"
    unset 'command_for_eval_array[-1]' # Remove output_path
    unset 'command_for_eval_array[-1]' # Remove redirect_mode

    if [[ ! -w "$base_path" ]]; then
      return 13 # EACCES
    fi

    command_for_eval_array+=("| tee $output_path")
  fi

  # Convert command_for_eval to a simple string
  command_for_eval=$(str_strip "${command_for_eval_array[*]}")

  case "$flag" in
    SILENT) ;;
    COMPLAIN)
      complain "$command_for_eval"
      ;;
    WARNING)
      warning "$command_for_eval"
      ;;
    SUCCESS)
      success "$command_for_eval"
      ;;
    HIGHLIGHT_CMD)
      warning "$command_for_eval"
      ;;
    TEST_MODE)
      say "$command_for_eval"
      return 0
      ;;
    *)
      say "$command_for_eval"
      ;;
  esac

  eval "$command_for_eval"
}

# Checks if a directory is a kernel tree root
#
# @DIR A directory path
#
# Returns:
# True if given dir is a kernel tree root and false otherwise.
function is_kernel_root()
{
  local -r DIR="$*"

  # The following files are some of the files expected to be at a linux
  # tree root and not expected to change. Their presence (or abscense)
  # is used to tell if a directory is a linux tree root or not. (They
  # are the same ones used by get_maintainer.pl)
  if [[ -f "${DIR}/COPYING" && -f "${DIR}/CREDITS" && -f "${DIR}/Kbuild" && -e "${DIR}/MAINTAINERS" && -f "${DIR}/Makefile" && -f "${DIR}/README" && -d "${DIR}/Documentation" && -d "${DIR}/arch" && -d "${DIR}/include" && -d "${DIR}/drivers" && -d "${DIR}/fs" && -d "${DIR}/init" && -d "${DIR}/ipc" && -d "${DIR}/kernel" && -d "${DIR}/lib" && -d "${DIR}/scripts" ]]; then
    return 0
  fi
  return 1
}

# Finds the root of the linux kernel repo containing the given file
#
# @FILE_OR_DIR The argument is a directory of file path
#
# Returns:
# The path of the kernel tree root (string) which the file or dir belongs to, or
# an empty string if no root was found.
function find_kernel_root()
{
  local -r FILE_OR_DIR="$*"
  local current_dir
  local kernel_root=''

  if [[ -f "$FILE_OR_DIR" ]]; then
    current_dir="$(dirname "$FILE_OR_DIR")"
  else
    current_dir="$FILE_OR_DIR"
  fi

  if is_kernel_root "$current_dir"; then
    kernel_root="$current_dir"
  else
    while [[ "$current_dir" != '.' && "$current_dir" != '/' ]]; do
      current_dir="$(dirname "$current_dir")"
      if is_kernel_root "$current_dir"; then
        kernel_root="$current_dir"
        break
      fi
    done
  fi

  printf '%s\n' "$kernel_root"
}

# Get the kernel release based on the command kernelrelease.
#
# @flag How to display a command, the default value is
#   "SILENT". For more options see `src/kwlib.sh` function `cmd_manager`
#
# Note: Make sure that you called is_kernel_root before trying to execute this
# function.
function get_kernel_release()
{
  local flag="$1"
  local cmd='make kernelrelease'

  flag=${flag:-'SILENT'}

  cmd_manager "$flag" "$cmd"
}

# Get the kernel version name.
#
# @flag How to display a command, the default value is
#   "SILENT". For more options see `src/kwlib.sh` function `cmd_manager`
#
# Note: Make sure that you called is_kernel_root before trying to execute this
# function.
function get_kernel_version()
{
  local flag="$1"
  local cmd='make kernelversion'

  flag=${flag:-'SILENT'}

  cmd_manager "$flag" "$cmd"
}

# Checks if the given path is a patch file
#
# @FILE_PATH The argument is the path
#
# Returns:
# True if given path is a patch file and false otherwise.
function is_a_patch()
{
  local -r FILE_PATH="$*"
  local file_content

  if [[ ! -f "$FILE_PATH" ]]; then
    return 1
  fi

  file_content=$(cat "$FILE_PATH")

  # The following array stores strings that are expected to be present
  # in a patch file. The absence of any of these strings makes the
  # given file be considered NOT a patch
  local -ar PATCH_EXPECTED_STRINGS=(
    'diff --git'
    '---'
    '@@'
  )

  for expected_str in "${PATCH_EXPECTED_STRINGS[@]}"; do
    if [[ ! "$file_content" =~ $expected_str ]]; then
      return 1
    fi
  done

  return 0
}

# This function joins one path components intelligently. The return value is
# the concatenation of path and any members.
#
# @target_path Path to join
# @member Component to join the path
#
# Returns:
# Return the concatenation of path and member, removing any extra slashes '/'
function join_path()
{
  local target_path=$1
  local member=$2
  local joined

  # TODO: Extended pattern matching. We should consider to use it as a default
  # in this project.
  shopt -s extglob
  member=${member%%+(/)}
  member=${member##+(/)}

  joined="${target_path%%+(/)}/$member"

  printf '%s\n' "$joined" | tr -s '/'
}

# This function tries to identify the OS distribution. In order to make it work
# as expected, it is required to inform the root path. This function is useful
# for plugins; because of this, we limited here the supported distributions.
#
# Note: We handle OS family instead of a specific distro, for example, Ubuntu
# and Mint are Debian based distro. Currently, this approach works well and
# avoids code duplication, in the future, if the distros families changes in
# the way that they handle Linux Kernel we probably have to change our
# approach.

# @root_path Expects the root path wherein we can find the /etc
#
# Returns:
# It returns the distro name in lowercase, otherwise return none.
function detect_distro()
{
  local root_path="$1"
  local str_check="$2"
  local distro='none'
  local etc_path

  etc_path=$(join_path "$root_path" /etc)

  if [[ -n "$str_check" ]]; then
    distro="$str_check"
  elif [[ -d $etc_path ]]; then
    distro=$(cat "$etc_path"/*-release | grep -w ID | cut -d = -f 2)
  fi

  # ArchLinux family
  if [[ "$distro" =~ 'arch' ]] || [[ "$distro" =~ 'manjaro' ]]; then
    printf '%s\n' 'arch'
  # Debian family
  elif [[ "$distro" =~ 'debian' ]] || [[ "$distro" =~ 'ubuntu' ]]; then
    printf '%s\n' 'debian'
  else
    printf '%s\n' 'none'
  fi
}

# This function maps a label with a value that is used to store statistics data
# related to kw. It also manages the database creation, any data that should be
# handled as a kw statistics should use this function.
#
# @label Label name used to identify a value
# @value Value should be an integer number
#
# Return:
# Print a execution time info
function statistics_manager()
{
  local label="$1"
  local value="$2"
  local day
  local year_month_dir
  local day_path

  day=$(date +%d)
  year_month_dir=$(date +%Y/%m)
  day_path="$KW_DATA_DIR/statistics/$year_month_dir/$day"

  elapsed_time=$(date -d@"$value" -u +%H:%M:%S)
  say "-> Execution time: $elapsed_time"

  [[ ${configurations[disable_statistics_data_track]} == 'yes' ]] && return

  update_statistics_database "$year_month_dir" "$day"
  store_statistics_data "$day_path" "$label" "$value"
}

# This function is part of the statistics feature and it is responsible for
# managing the database by following the calendar organization.
#
# @year_month_dir Current year
# @day Current day of the week
function update_statistics_database()
{
  local year_month_path="$1"
  local day="$2"

  [[ -z "$day" || -z "$year_month_path" ]] && return 22 # EINVAL

  mkdir -p "$KW_DATA_DIR/statistics/$year_month_path"
  touch "$KW_DATA_DIR/statistics/$year_month_path/$day"
}

# This function save the information directly to a file.
#
# @day_path Current day
# @label Label used to identify a value
# @value An integer number associated to a label
function store_statistics_data()
{
  local day_path="$1"
  local label="$2"
  local value="$3"

  [[ ! -f "$day_path" || -z "$label" || -z "$value" ]] && return 22 # EINVAL

  printf '%s\n' "$label $value" >> "$day_path"
}

# This function checks if a certain command can be run
#
# @command The whole command that is meant to be executed
function command_exists()
{
  local command="$1"
  #shellcheck disable=SC2206 #FIXME: see issue #388
  local package=($command)

  if [[ -x "$(command -v "${package[@]}")" ]]; then
    return 0
  fi
  return 22 # EINVAL
}

# This function exits with a custom error message
#
# @err The error code to be used on exit, it takes the return code of the
#        last command executed as default
# @msg The custom message to be displayed
function exit_msg()
{
  local err=${2:-"$?"}
  local msg=${1:-'Something went wrong!'}

  complain "$msg"
  exit "$err"
}

# This function parses command line arguments. Each option may be
# followed by a one colon to indicate it has a required argument, and by
# two colons to indicate it has an optional argument. If any errors are
# found, this will print an error message to stderr indicating it.
#
# @short_options Short options to be accepted
# @long_options Long options to be accepted
# @{@:2} Arguments to be parsed
#
# Returns:
# Parsed command line arguments.
function kw_parse()
{
  local short_options="$1"
  local long_options="$2"
  shift 2

  getopt -q --options "$short_options" \
    --longoptions "$long_options" \
    -- "$@"
}

# This function gets the error messages for a kw_parse call. The same
# arguments passed to kw_parse should be passed to this function.
#
# @name Name to be prefixed in error messages
# @short_options Short options to be accepted
# @long_options Long options to be accepted
# @{@:2} Arguments to be parsed
#
# Returns:
# Error messages separated by a newline and prefixed with @name
function kw_parse_get_errors()
{
  local name="$1"
  local short_options="$2"
  local long_options="$3"
  shift 3

  {
    getopt --name "$name" \
      --options "$short_options" \
      --longoptions "$long_options" \
      -- "$@" > /dev/null
  } 2>&1
}

# This function compresses a given path to a .tar.gz file
#
# @go_to_path_to_compress Directory to go into
# @file_path Where the compressed directory will be stored
# @compression_type compression program used
# @dir_name The directory to be compressed, inside go_to_path_to_compress
# @flag How to display (or not) the command used
function generate_tarball()
{
  local go_to_path_to_compress="$1"
  local file_path="$2"
  local compression_type="$3"
  local dir_name="$4"
  local flag="$5"
  local ret
  local cmd

  flag=${flag:-'SILENT'}
  dir_name=${dir_name:-'.'}

  if [[ ! -d "$go_to_path_to_compress" ]]; then
    complain "$go_to_path_to_compress" 'does not exist'
    exit 22 #EINVAL
  fi

  if [[ -n "$compression_type" ]]; then
    if [[ "${compression_programs[*]}" =~ $compression_type ]]; then
      compression_type="--$compression_type"
    else
      complain 'Invalid compression type:' "$compression_type"
      return 22 # EINVAL
    fi
  fi

  compression_type=${compression_type:-'--auto-compress'}

  # -C: Go to $go_to_path_to_compress directory
  # -cf: Compress the directory named $dir_name (inside $go_to_path_to_compress) to
  #      $file_path
  cmd="tar -C $go_to_path_to_compress $compression_type -cf $file_path $dir_name"
  cmd_manager "$flag" "$cmd"

  ret="$?"

  if [[ "$ret" != 0 ]]; then
    complain 'Error archiving modules.'
    exit "$ret"
  fi
}

# This function extracts a .tar.gz file to a given path
#
# @file_to_extract The path to the file to extract from
# @path Where to extract the file
# @compression_type compression program used
# @flag How to display (or not) the command used
function extract_tarball()
{
  local file_to_extract="$1"
  local path="$2"
  local compression_type="$3"
  local flag="$4"
  local cmd

  flag=${flag:-'SILENT'}

  if [[ ! -f "$file_to_extract" ]]; then
    complain 'We could not find' "$file_to_extract"
    exit 22 #EINVAL
  fi

  if [[ ! -d "$path" ]]; then
    complain "$path" 'does not exist'
    exit 22 #EINVAL
  fi

  if [[ -n "$compression_type" ]]; then
    if [[ "${compression_programs[*]}" =~ $compression_type ]]; then
      compression_type="--$compression_type"
    else
      complain 'Invalid compression type:' "$compression_type"
      return 22 # EINVAL
    fi
  fi

  compression_type=${compression_type:-'--auto-compress'}

  cmd="tar $compression_type -xf $file_to_extract -C $path"
  cmd_manager "$flag" "$cmd"
}

# Given a file path, this function returns only the file name. For instance, for
# a file path 'documents/file.txt', it returns file.txt. If the file path is
# empty, then this function returns an empty string.
#
# @ file_path: path to a file
function get_file_name_from_path()
{
  local file_path="$1"

  printf '%s\n' "${file_path##*/}"
}

# Checks if the command is being run inside a git work-tree
#
# @flag: How to display (or not) the command used
#
# Returns:
# 0 if is inside a git work-tree root and 128 otherwise.
function is_inside_work_tree()
{
  local flag="$1"
  local cmd='git rev-parse --is-inside-work-tree &> /dev/null'

  flag=${flag:-'SILENT'}

  cmd_manager "$flag" "$cmd"
}

# Get all instances of a given git config with their scope
#
# @config: Given configuration to get the values of
# @scope:  Limit search to given scope
# @flag:   How to display (or not) the command used
# @output: Array to store the values at a given scope
# @scp:    Used to go through all scopes
#
# Returns:
# All values of the given config with their respective scopes
function get_all_git_config()
{
  local config="$1"
  local scope="$2"
  local flag="$3"
  local cmd='git config --get-all'
  local -A output
  local scp

  flag=${flag:-'SILENT'}

  for scp in {'global','local'}; do
    if [[ -z "$scope" || "$scope" == "$scp" ]]; then
      output["$scp"]="$(cmd_manager "$flag" "$cmd --$scp $config" | sed -E "s/^/$scp\t/g")"
    fi
  done

  printf '%s\n' "${output[@]}"
}

# Get all instances of a given git config with their scope
#
# @regexp: Given regular expression to find associated values
# @scope:  Limit search to given scope
# @flag:   How to display (or not) the command used
# @output: Array to store the values at a given scope
# @scp:    Used to go through all scopes
#
# Returns:
# All config values that match the given regular expression
function get_git_config_regex()
{
  local regexp="$1"
  local scope="$2"
  local flag="$3"
  local cmd='git config --get-regexp'
  local -A output
  local scp

  flag=${flag:-'SILENT'}

  for scp in {'global','local'}; do
    if [[ -z "$scope" || "$scope" == "$scp" ]]; then
      output["$scp"]="$(cmd_manager "$flag" "$cmd --$scp '$regexp'" | sed -E "s/^/$scp\t/g")"
    fi
  done

  printf '%s\n' "${output[@]}"
}
