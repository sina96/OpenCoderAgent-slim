#!/usr/bin/env bash

#############################################################################
# OpenAgents Control Installer
# Interactive installer for OpenCode agents, commands, tools, and plugins
#
# Compatible with:
# - macOS (bash 3.2+)
# - Linux (bash 3.2+)
# - Windows (Git Bash, WSL)
#############################################################################

set -e

# Detect platform
PLATFORM="$(uname -s)"
case "$PLATFORM" in
    Linux*)     PLATFORM="Linux";;
    Darwin*)    PLATFORM="macOS";;
    CYGWIN*|MINGW*|MSYS*) PLATFORM="Windows";;
    *)          PLATFORM="Unknown";;
esac

# Colors for output (disable on Windows if not supported)
if [ "$PLATFORM" = "Windows" ] && [ -z "$WT_SESSION" ] && [ -z "$ConEmuPID" ]; then
    # Basic Windows terminal without color support
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
fi

# Configuration
REPO_URL="https://github.com/sina96/OpenCoderAgent-slim"
BRANCH="${OPENCODE_BRANCH:-main}"  # Allow override via environment variable
RAW_URL="https://raw.githubusercontent.com/sina96/OpenCoderAgent-slim/${BRANCH}"

# Registry URL - supports local fallback for development
# Priority: 1) REGISTRY_URL env var, 2) Local registry.json, 3) Remote GitHub
if [ -n "$REGISTRY_URL" ]; then
    # Use explicitly set REGISTRY_URL (for testing)
    :
elif [ -f "./registry.json" ]; then
    # Use local registry.json if it exists (for development)
    REGISTRY_URL="file://$(pwd)/registry.json"
else
    # Default to remote GitHub registry
    REGISTRY_URL="${RAW_URL}/registry.json"
fi

INSTALL_DIR="${OPENCODE_INSTALL_DIR:-.opencode}"  # Allow override via environment variable
TEMP_DIR="/tmp/opencode-installer-$$"

# Cleanup temp directory on exit (success or failure)
trap 'rm -rf "$TEMP_DIR" 2>/dev/null || true' EXIT INT TERM

# Global variables
SELECTED_COMPONENTS=()
INSTALL_MODE=""
PROFILE=""
NON_INTERACTIVE=false
CUSTOM_INSTALL_DIR=""  # Set via --install-dir argument

# Connected Providers configuration
CONNECTED_PROVIDERS_CONFIGURED=false
PROVIDER_CLAUDE=false
PROVIDER_CLAUDE_PLAN=""
PROVIDER_OPENAI=false
PROVIDER_OPENCODE_ZEN=false
PROVIDER_GOOGLE_GEMINI=false

# Models recommended for free usage:
FREE_MODELS=("opencode/big-pickle" "opencode/kimi-k2.5-free" "opencode/minimax-m2.1-free")


#############################################################################
# Utility Functions
#############################################################################

jq_exec() {
    local output
    output=$(jq -r "$@")
    local ret=$?
    printf "%s\n" "$output" | tr -d '\r'
    return $ret
}

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║           OpenCoderAgent-slim Installer v0.1.0                 ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_step() {
    echo -e "\n${MAGENTA}${BOLD}▶${NC} $1\n"
}

#############################################################################
# Path Handling (Cross-Platform)
#############################################################################

normalize_and_validate_path() {
    local input_path="$1"
    local normalized_path
    
    # Handle empty path
    if [ -z "$input_path" ]; then
        echo ""
        return 1
    fi
    
    # Expand tilde to $HOME (works on Linux, macOS, Windows Git Bash)
    if [[ $input_path == ~* ]]; then
        normalized_path="${HOME}${input_path:1}"
    else
        normalized_path="$input_path"
    fi
    
    # Convert backslashes to forward slashes (Windows compatibility)
    normalized_path="${normalized_path//\\//}"
    
    # Remove trailing slashes
    normalized_path="${normalized_path%/}"
    
    # If path is relative, make it absolute based on current directory
    if [[ ! "$normalized_path" = /* ]] && [[ ! "$normalized_path" =~ ^[A-Za-z]: ]]; then
        normalized_path="$(pwd)/${normalized_path}"
    fi
    
    echo "$normalized_path"
    return 0
}

validate_install_path() {
    local path="$1"
    local parent_dir
    
    # Get parent directory
    parent_dir="$(dirname "$path")"
    
    # Check if parent directory exists
    if [ ! -d "$parent_dir" ]; then
        print_error "Parent directory does not exist: $parent_dir"
        return 1
    fi
    
    # Check if parent directory is writable
    if [ ! -w "$parent_dir" ]; then
        print_error "No write permission for directory: $parent_dir"
        return 1
    fi
    
    # If target directory exists, check if it's writable
    if [ -d "$path" ] && [ ! -w "$path" ]; then
        print_error "No write permission for directory: $path"
        return 1
    fi
    
    return 0
}

get_global_install_path() {
    # Return platform-appropriate global installation path
    case "$PLATFORM" in
        macOS)
            # macOS: Use XDG standard (consistent with Linux)
            echo "${HOME}/.config/opencode"
            ;;
        Linux)
            echo "${HOME}/.config/opencode"
            ;;
        Windows)
            # Windows Git Bash/WSL: Use same as Linux
            echo "${HOME}/.config/opencode"
            ;;
        *)
            echo "${HOME}/.config/opencode"
            ;;
    esac
}

#############################################################################
# Dependency Checks
#############################################################################

check_bash_version() {
    # Check bash version (need 3.2+)
    local bash_version="${BASH_VERSION%%.*}"
    if [ "$bash_version" -lt 3 ]; then
        echo "Error: This script requires Bash 3.2 or higher"
        echo "Current version: $BASH_VERSION"
        echo ""
        echo "Please upgrade bash or use a different shell:"
        echo "  macOS:   brew install bash"
        echo "  Linux:   Use your package manager to update bash"
        echo "  Windows: Use Git Bash or WSL"
        exit 1
    fi
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install them:"
        case "$PLATFORM" in
            macOS)
                echo "  brew install ${missing_deps[*]}"
                ;;
            Linux)
                echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
                echo "  Fedora/RHEL:   sudo dnf install ${missing_deps[*]}"
                echo "  Arch:          sudo pacman -S ${missing_deps[*]}"
                ;;
            Windows)
                echo "  Git Bash: Install via https://git-scm.com/"
                echo "  WSL:      sudo apt-get install ${missing_deps[*]}"
                echo "  Scoop:    scoop install ${missing_deps[*]}"
                ;;
            *)
                echo "  Use your package manager to install: ${missing_deps[*]}"
                ;;
        esac
        exit 1
    fi
    
    print_success "All dependencies found"
}

#############################################################################
# Registry Functions
#############################################################################

fetch_registry() {
    print_step "Fetching component registry..."
    
    mkdir -p "$TEMP_DIR"
    
    # Handle local file:// URLs
    if [[ "$REGISTRY_URL" == file://* ]]; then
        local local_path="${REGISTRY_URL#file://}"
        if [ -f "$local_path" ]; then
            cp "$local_path" "$TEMP_DIR/registry.json"
            print_success "Using local registry: $local_path"
        else
            print_error "Local registry not found: $local_path"
            exit 1
        fi
    else
        # Fetch from remote URL
        if ! curl -fsSL "$REGISTRY_URL" -o "$TEMP_DIR/registry.json"; then
            print_error "Failed to fetch registry from $REGISTRY_URL"
            exit 1
        fi
        print_success "Registry fetched successfully"
    fi

    print_success "Registry fetched successfully from $REGISTRY_URL"
}

get_profile_components() {
    local profile=$1
    jq_exec ".profiles.${profile}.components[]?" "$TEMP_DIR/registry.json"
}

get_component_info() {
    local component_id=$1
    local component_type=$2
    
    if [ "$component_type" = "context" ] && [[ "$component_id" == */* ]]; then
        jq_exec "first(.components.contexts[]? | select(.path == \".opencode/context/${component_id}.md\"))" "$TEMP_DIR/registry.json"
        return
    fi

    jq_exec ".components.${component_type}[]? | select(.id == \"${component_id}\" or (.aliases // [] | index(\"${component_id}\")))" "$TEMP_DIR/registry.json"
}

resolve_component_path() {
    local component_type=$1
    local component_id=$2
    local registry_key
    registry_key=$(get_registry_key "$component_type")

    if [ "$component_type" = "context" ] && [[ "$component_id" == */* ]]; then
        jq_exec "first(.components.contexts[]? | select(.path == \".opencode/context/${component_id}.md\") | .path)" "$TEMP_DIR/registry.json"
        return
    fi

    jq_exec ".components.${registry_key}[]? | select(.id == \"${component_id}\" or (.aliases // [] | index(\"${component_id}\"))) | .path" "$TEMP_DIR/registry.json"
}

# Helper function to get the correct registry key for a component type
get_registry_key() {
    local type=$1
    # Most types are pluralized, but 'config' stays singular
    case "$type" in
        config) echo "config" ;;
        *) echo "${type}s" ;;
    esac
}

# Helper function to convert registry path to installation path
# Registry paths are like ".opencode/agent/foo.md"
# We need to replace ".opencode" with the actual INSTALL_DIR
get_install_path() {
    local registry_path=$1
    # Strip leading .opencode/ if present
    local relative_path="${registry_path#.opencode/}"
    # Return INSTALL_DIR + relative path
    echo "${INSTALL_DIR}/${relative_path}"
}

expand_context_wildcard() {
    local pattern=$1
    local prefix="${pattern%%\**}"

    prefix="${prefix%/}"
    if [ -n "$prefix" ]; then
        prefix="${prefix}/"
    fi

    jq_exec ".components.contexts[]? | select(.path | startswith(\".opencode/context/${prefix}\")) | .path | sub(\"^\\\\.opencode/context/\"; \"\") | sub(\"\\\\.md$\"; \"\")" "$TEMP_DIR/registry.json"
}

expand_selected_components() {
    local expanded=()

    for comp in "${SELECTED_COMPONENTS[@]}"; do
        local type="${comp%%:*}"
        local id="${comp##*:}"

        if [[ "$id" == *"*"* ]]; then
            if [ "$type" != "context" ]; then
                print_warning "Wildcard only supported for context components: ${comp}"
                continue
            fi

            local matches
            matches=$(expand_context_wildcard "$id")

            if [ -z "$matches" ]; then
                print_warning "No contexts matched: ${comp}"
                continue
            fi

            while IFS= read -r match; do
                [ -n "$match" ] && expanded+=("context:${match}")
            done <<< "$matches"
            continue
        fi

        expanded+=("$comp")
    done

    local deduped=()
    for comp in "${expanded[@]}"; do
        local found=0
        for existing in "${deduped[@]}"; do
            if [ "$existing" = "$comp" ]; then
                found=1
                break
            fi
        done
        if [ "$found" -eq 0 ]; then
            deduped+=("$comp")
        fi
    done

    SELECTED_COMPONENTS=("${deduped[@]}")
}

resolve_dependencies() {
    local component=$1
    local type="${component%%:*}"
    local id="${component##*:}"
    
    # Get the correct registry key (handles singular/plural)
    local registry_key
    registry_key=$(get_registry_key "$type")
    
    # Get dependencies for this component
    local deps
    deps=$(jq_exec ".components.${registry_key}[] | select(.id == \"${id}\" or (.aliases // [] | index(\"${id}\"))) | .dependencies[]?" "$TEMP_DIR/registry.json" 2>/dev/null || echo "")
    
    if [ -n "$deps" ]; then
        for dep in $deps; do
            if [[ "$dep" == *"*"* ]]; then
                local dep_type="${dep%%:*}"
                local dep_id="${dep##*:}"

                if [ "$dep_type" = "context" ]; then
                    local matched
                    matched=$(expand_context_wildcard "$dep_id")

                    if [ -z "$matched" ]; then
                        print_warning "No contexts matched dependency: ${dep}"
                        continue
                    fi

                    while IFS= read -r match; do
                        local expanded_dep="context:${match}"
                        local found=0
                        for existing in "${SELECTED_COMPONENTS[@]}"; do
                            if [ "$existing" = "$expanded_dep" ]; then
                                found=1
                                break
                            fi
                        done
                        if [ "$found" -eq 0 ]; then
                            SELECTED_COMPONENTS+=("$expanded_dep")
                            resolve_dependencies "$expanded_dep"
                        fi
                    done <<< "$matched"
                    continue
                fi
            fi

            # Add dependency if not already in list
            local found=0
            for existing in "${SELECTED_COMPONENTS[@]}"; do
                if [ "$existing" = "$dep" ]; then
                    found=1
                    break
                fi
            done
            if [ "$found" -eq 0 ]; then
                SELECTED_COMPONENTS+=("$dep")
                # Recursively resolve dependencies
                resolve_dependencies "$dep"
            fi
        done
    fi
}

#############################################################################
# Installation Mode Selection
#############################################################################

check_interactive_mode() {
    # Check if stdin is a terminal (not piped from curl)
    if [ ! -t 0 ]; then
        print_header
        print_error "Interactive mode requires a terminal"
        echo ""
        echo "You're running this script in a pipe (e.g., curl | bash)"
        echo "For interactive mode, download the script first:"
        echo ""
        echo -e "${CYAN}# Download the script${NC}"
        echo "curl -fsSL https://raw.githubusercontent.com/sina96/OpenCoderAgent-slim/main/install.sh -o install.sh"
        echo ""
        echo -e "${CYAN}# Run interactively${NC}"
        echo "bash install.sh"
        echo ""
        echo "Or use a profile directly:"
        echo ""
        echo -e "${CYAN}# Quick install with profile${NC}"
        echo "curl -fsSL https://raw.githubusercontent.com/sina96/OpenCoderAgent-slim/main/install.sh | bash -s essential"
        echo ""
        echo "Available profiles: minimalCoder, standardCoder, extendedCoder, advanced"
        echo ""
        cleanup_and_exit 1
    fi
}

show_install_location_menu() {
    check_interactive_mode
    
    clear
    print_header
    
    local global_path
    global_path=$(get_global_install_path)
    
    echo -e "${BOLD}Choose installation location:${NC}\n"
    echo -e "  ${GREEN}1) Local${NC} - Install to ${CYAN}.opencode/${NC} in current directory"
    echo "     (Best for project-specific agents)"
    echo ""
    echo -e "  ${BLUE}2) Global${NC} - Install to ${CYAN}${global_path}${NC}"
    echo "     (Best for user-wide agents available everywhere)"
    echo ""
    echo -e "  ${MAGENTA}3) Custom${NC} - Enter exact path"
    echo "     Examples:"
    case "$PLATFORM" in
        Windows)
            echo "       ${CYAN}C:/Users/username/my-agents${NC} or ${CYAN}~/my-agents${NC}"
            ;;
        *)
            echo "       ${CYAN}/home/username/my-agents${NC} or ${CYAN}~/my-agents${NC}"
            ;;
    esac
    echo ""
    echo "  4) Back / Exit"
    echo ""
    read -r -p "Enter your choice [1-4]: " location_choice
    
    case $location_choice in
        1)
            INSTALL_DIR=".opencode"
            print_success "Installing to local directory: .opencode/"
            sleep 1
            ;;
        2)
            INSTALL_DIR="$global_path"
            print_success "Installing to global directory: $global_path"
            sleep 1
            ;;
        3)
            echo ""
            read -r -p "Enter installation path: " custom_path
            
            if [ -z "$custom_path" ]; then
                print_error "No path entered"
                sleep 2
                show_install_location_menu
                return
            fi
            
            local normalized_path
            normalized_path=$(normalize_and_validate_path "$custom_path")
            
            if ! normalize_and_validate_path "$custom_path" > /dev/null; then
                print_error "Invalid path"
                sleep 2
                show_install_location_menu
                return
            fi
            
            if ! validate_install_path "$normalized_path"; then
                echo ""
                read -r -p "Continue anyway? [y/N]: " continue_choice
                if [[ ! $continue_choice =~ ^[Yy] ]]; then
                    show_install_location_menu
                    return
                fi
            fi
            
            INSTALL_DIR="$normalized_path"
            print_success "Installing to custom directory: $INSTALL_DIR"
            sleep 1
            ;;
        4)
            cleanup_and_exit 0
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            show_install_location_menu
            return
            ;;
    esac
}

#############################################################################
# Connected Providers Configuration
#############################################################################

fetch_latest_models() {
    local api_url="https://models.dev/api.json"
    local providers=("anthropic" "openai" "opencode" "google")
    local models_count=30
    
    print_info "Fetching latest models from models.dev..."
    
    # Fetch the API
    local api_response
    api_response=$(curl -fsSL "$api_url" 2>/dev/null)
    
    if [ -z "$api_response" ]; then
        print_error "Failed to fetch models from $api_url"
        return 1
    fi
    
    # Initialize global array
    LATEST_MODELS=()
    
    # Process each provider
    for provider in "${providers[@]}"; do
        # Extract models for this provider and get the last 5
        local provider_models
        provider_models=$(echo "$api_response" | jq_exec ".${provider}.models | to_entries | .[-${models_count}:][] | \"\(.value.id)|\(.value.family)\"" 2>/dev/null)
        
        if [ -z "$provider_models" ]; then
            print_warning "No models found for provider: $provider"
            continue
        fi
        
        # Add each model to the array
        while IFS='|' read -r model_id model_family; do
            if [ -n "$model_id" ] && [ -n "$model_family" ]; then
                LATEST_MODELS+=("${provider}|${model_id}|${model_family}")
            fi
        done <<< "$provider_models"
    done
    
    # Echo the array for testing
    if [ ${#LATEST_MODELS[@]} -gt 0 ]; then
        print_success "Fetched ${#LATEST_MODELS[@]} models"
        #print_info "Latest models:"
        #for model in "${LATEST_MODELS[@]}"; do
        #    echo "  $model"
        #done
    else
        print_warning "No models were fetched"
        return 1
    fi
    
    return 0
}

model_exists() {
    local provider="$1"
    local model_id="$2"
    for model in "${LATEST_MODELS[@]}"; do
        # LATEST_MODELS format: provider|model_id|family
        if [[ "$model" == "${provider}|${model_id}|"* ]]; then
            return 0
        fi
    done
    return 1
}

show_connected_providers_menu() {
    check_interactive_mode
    
    
    clear
    print_header
    
    echo -e "${BOLD}Connected Providers Configuration${NC}\n"
    echo "Configure which AI providers you have connected to OpenCode."
    echo ""
    
    # First question - ask if they want to configure at all
    echo -e "${CYAN}Do you want to configure connected providers?${NC}"
    echo "  (y) Yes - configure each provider individually"
    echo "  (n) No - skip this step"
    echo ""
    read -r -p "Enter your choice [y/n]: " configure_providers_choice
    
    case $configure_providers_choice in
        [Nn])
            # No - just skip, will ask again next time
            print_info "Skipping provider configuration (you can configure later)"
            sleep 1
            return
            ;;
        [Yy])
            # Yes - proceed with individual questions
            CONNECTED_PROVIDERS_CONFIGURED=true
            echo ""
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            show_connected_providers_menu
            return
            ;;
    esac
    
    # Individual provider questions (no "no to all" option here)
    echo -e "${BOLD}Configure each provider:${NC}\n"
    
    echo ""

    # Claude
    read -r -p "Have you connected Claude? [y/N]: " claude_choice
    if [[ $claude_choice =~ ^[Yy] ]]; then
        PROVIDER_CLAUDE=true
        print_success "Claude: Connected"
        echo ""
    
        # Follow-up question for Claude plan
        echo -e "${CYAN}Which Claude plan do you have?${NC}"
        echo "  1) Claude Pro"
        echo "  2) Claude Max20"
        echo "  3) Claude Max100"
        echo "  4) Skip / Other"
        echo ""
        read -r -p "Enter your choice [1-4]: " claude_plan_choice
    
        case $claude_plan_choice in
            1)
                PROVIDER_CLAUDE_PLAN="pro"
                print_info "Plan: Claude Pro"
                ;;
            2)
                PROVIDER_CLAUDE_PLAN="max20"
                print_info "Plan: Claude Max20"
                ;;
            3)
                PROVIDER_CLAUDE_PLAN="max100"
                print_info "Plan: Claude Max100"
                ;;
            *)
                PROVIDER_CLAUDE_PLAN=""
                print_info "Plan: Not specified"
                ;;
        esac
    else
    print_info "Claude: Not connected"
    fi
    echo ""
    
    # OpenAI
    read -r -p "Have you connected OpenAI? [y/N]: " openai_choice
    if [[ $openai_choice =~ ^[Yy] ]]; then
        PROVIDER_OPENAI=true
        print_success "OpenAI: Connected"
    else
        print_info "OpenAI: Not connected"
    fi
    echo ""
    
    # Opencode-zen
    read -r -p "Have you connected Opencode-zen? [y/N]: " opencode_zen_choice
    if [[ $opencode_zen_choice =~ ^[Yy] ]]; then
        PROVIDER_OPENCODE_ZEN=true
        print_success "Opencode-zen: Connected"
    else
        print_info "Opencode-zen: Not connected"
    fi
    echo ""
    
    # Google Gemini
    read -r -p "Have you connected Google Gemini? [y/N]: " gemini_choice
    if [[ $gemini_choice =~ ^[Yy] ]]; then
        PROVIDER_GOOGLE_GEMINI=true
        print_success "Google Gemini: Connected"
    else
        print_info "Google Gemini: Not connected"
    fi
    echo ""
    
    # Summary
    echo -e "${BOLD}Provider Configuration Summary:${NC}"
    echo "  Claude: $([ "$PROVIDER_CLAUDE" = true ] && echo "✓ Connected ($PROVIDER_CLAUDE_PLAN)" || echo "✗ Not connected")"
    echo "  OpenAI: $([ "$PROVIDER_OPENAI" = true ] && echo "✓ Connected" || echo "✗ Not connected")"
    echo "  Opencode-zen: $([ "$PROVIDER_OPENCODE_ZEN" = true ] && echo "✓ Connected" || echo "✗ Not connected")"
    echo "  Google Gemini: $([ "$PROVIDER_GOOGLE_GEMINI" = true ] && echo "✓ Connected" || echo "✗ Not connected")"
    echo ""

    
    
}

show_main_menu() {
    check_interactive_mode
    
    clear
    print_header
    
    echo -e "${BOLD}Choose installation mode:${NC}\n"
    echo "  1) Quick Install (Choose a profile)"
    echo "  2) Custom Install (Pick individual components)"
    echo "  3) List Available Components"
    echo "  4) Exit"
    echo ""
    read -r -p "Enter your choice [1-4]: " choice
    
    case $choice in
        1) INSTALL_MODE="profile" ;;
        2) INSTALL_MODE="custom" ;;
        3) list_components; read -r -p "Press Enter to continue..."; show_main_menu ;;
        4) cleanup_and_exit 0 ;;
        *) print_error "Invalid choice"; sleep 2; show_main_menu ;;
    esac
}

#############################################################################
# Profile Installation
#############################################################################

show_profile_menu() {
    clear
    print_header
    
    echo -e "${BOLD}Available Installation Profiles:${NC}\n"
    
    # Minimal Coder profile
    local minimal_coder_name
    minimal_coder_name=$(jq_exec '.profiles.minimalCoder.name' "$TEMP_DIR/registry.json")
    local minimal_coder_desc
    minimal_coder_desc=$(jq_exec '.profiles.minimalCoder.description' "$TEMP_DIR/registry.json")
    local minimal_coder_count
    minimal_coder_count=$(jq_exec '.profiles.minimalCoder.components | length' "$TEMP_DIR/registry.json")
    echo -e "  ${GREEN}1) ${minimal_coder_name}${NC}"
    echo -e "     ${minimal_coder_desc}"
    echo -e "     Components: ${minimal_coder_count}\n"
    
    # Standard Coder profile
    local standard_coder_name
    standard_coder_name=$(jq_exec '.profiles.standardCoder.name' "$TEMP_DIR/registry.json")
    local standard_coder_desc
    standard_coder_desc=$(jq_exec '.profiles.standardCoder.description' "$TEMP_DIR/registry.json")
    local standard_coder_count
    standard_coder_count=$(jq_exec '.profiles.standardCoder.components | length' "$TEMP_DIR/registry.json")
    local standard_coder_badge
    standard_coder_badge=$(jq_exec '.profiles.standardCoder.badge // ""' "$TEMP_DIR/registry.json")
    if [ -n "$standard_coder_badge" ]; then
        echo -e "  ${BLUE}2) ${standard_coder_name} ${GREEN}[${standard_coder_badge}]${NC}"
    else
        echo -e "  ${BLUE}2) ${standard_coder_name}${NC}"
    fi
    echo -e "     ${standard_coder_desc}"
    echo -e "     Components: ${standard_coder_count}\n"

    
    # Extended Coder profile
    local extended_coder_name
    extended_coder_name=$(jq_exec '.profiles.extendedCoder.name' "$TEMP_DIR/registry.json")
    local extended_coder_desc
    extended_coder_desc=$(jq_exec '.profiles.extendedCoder.description' "$TEMP_DIR/registry.json")
    local extended_coder_count
    extended_coder_count=$(jq_exec '.profiles.extendedCoder.components | length' "$TEMP_DIR/registry.json")
    echo -e "  ${MAGENTA}4) ${extended_coder_name}${NC}"
    echo -e "     ${extended_coder_desc}"
    echo -e "     Components: ${extended_coder_count}\n"
    
    # Advanced (Meta-Level) profile
    local advanced_name
    advanced_name=$(jq_exec '.profiles.advanced.name' "$TEMP_DIR/registry.json")
    local advanced_desc
    advanced_desc=$(jq_exec '.profiles.advanced.description' "$TEMP_DIR/registry.json")
    local advanced_count
    advanced_count=$(jq_exec '.profiles.advanced.components | length' "$TEMP_DIR/registry.json")
    echo -e "  ${YELLOW}5) ${advanced_name}${NC}"
    echo -e "     ${advanced_desc}"
    echo -e "     Components: ${advanced_count}\n"
    
    echo "  6) Back to main menu"
    echo ""
    read -r -p "Enter your choice [1-6]: " choice
    
    case $choice in
        1) PROFILE="minimalCoder" ;;
        2) PROFILE="standardCoder" ;;
        3) PROFILE="extendedCoder" ;;
        5) PROFILE="advanced" ;;
        6) show_main_menu; return ;;
        *) print_error "Invalid choice"; sleep 2; show_profile_menu; return ;;
    esac  
    
    # Load profile components (compatible with bash 3.2+)
    SELECTED_COMPONENTS=()
    local temp_file="$TEMP_DIR/components.tmp"
    get_profile_components "$PROFILE" > "$temp_file"
    while IFS= read -r component; do
        [ -n "$component" ] && SELECTED_COMPONENTS+=("$component")
    done < "$temp_file"

    expand_selected_components
    
    # Resolve dependencies for profile installs
    print_step "Resolving dependencies..."
    local original_count=${#SELECTED_COMPONENTS[@]}
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        resolve_dependencies "$comp"
    done
    
    local new_count=${#SELECTED_COMPONENTS[@]}
    if [ "$new_count" -gt "$original_count" ]; then
        local added=$((new_count - original_count))
        print_info "Added $added dependencies"
    fi
    
    show_installation_preview
}

#############################################################################
# Custom Component Selection
#############################################################################

show_custom_menu() {
    clear
    print_header
    
    echo -e "${BOLD}Select component categories to install:${NC}\n"
    echo "Use space to toggle, Enter to continue"
    echo ""
    
    local categories=("agents" "subagents" "commands" "tools" "plugins" "skills" "contexts" "config")
    local selected_categories=()
    
    # Simple selection (for now, we'll make it interactive later)
    echo "Available categories:"
    for i in "${!categories[@]}"; do
        local cat="${categories[$i]}"
        local count
        count=$(jq_exec ".components.${cat} | length" "$TEMP_DIR/registry.json")
        local cat_display
        cat_display=$(echo "$cat" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
        echo "  $((i+1))) ${cat_display} (${count} available)"
    done
    echo "  $((${#categories[@]}+1))) Select All"
    echo "  $((${#categories[@]}+2))) Continue to component selection"
    echo "  $((${#categories[@]}+3))) Back to main menu"
    echo ""
    
    read -r -p "Enter category numbers (space-separated) or option: " -a selections
    
    for sel in "${selections[@]}"; do
        if [ "$sel" -eq $((${#categories[@]}+1)) ]; then
            selected_categories=("${categories[@]}")
            break
        elif [ "$sel" -eq $((${#categories[@]}+2)) ]; then
            break
        elif [ "$sel" -eq $((${#categories[@]}+3)) ]; then
            show_main_menu
            return
        elif [ "$sel" -ge 1 ] && [ "$sel" -le ${#categories[@]} ]; then
            selected_categories+=("${categories[$((sel-1))]}")
        fi
    done
    
    if [ ${#selected_categories[@]} -eq 0 ]; then
        print_warning "No categories selected"
        sleep 2
        show_custom_menu
        return
    fi
    
    show_component_selection "${selected_categories[@]}"
}

show_component_selection() {
    local categories=("$@")
    clear
    print_header
    
    echo -e "${BOLD}Select components to install:${NC}\n"
    
    local all_components=()
    local component_details=()
    
    for category in "${categories[@]}"; do
        local cat_display
        cat_display=$(echo "$category" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
        echo -e "${CYAN}${BOLD}${cat_display}:${NC}"
        
        local components
        components=$(jq_exec ".components.${category}[]? | .id" "$TEMP_DIR/registry.json")
        
        local idx=1
        while IFS= read -r comp_id; do
            local comp_name
            comp_name=$(jq_exec ".components.${category}[]? | select(.id == \"${comp_id}\") | .name" "$TEMP_DIR/registry.json")
            local comp_desc
            comp_desc=$(jq_exec ".components.${category}[]? | select(.id == \"${comp_id}\") | .description" "$TEMP_DIR/registry.json")
            
            echo "  ${idx}) ${comp_name}"
            echo "     ${comp_desc}"
            
            all_components+=("${category}:${comp_id}")
            component_details+=("${comp_name}|${comp_desc}")
            
            idx=$((idx+1))
        done <<< "$components"
        
        echo ""
    done
    
    echo "Enter component numbers (space-separated), 'all' for all, or 'done' to continue:"
    read -r -a selections
    
    for sel in "${selections[@]}"; do
        if [ "$sel" = "all" ]; then
            SELECTED_COMPONENTS=("${all_components[@]}")
            break
        elif [ "$sel" = "done" ]; then
            break
        elif [ "$sel" -ge 1 ] && [ "$sel" -le ${#all_components[@]} ]; then
            SELECTED_COMPONENTS+=("${all_components[$((sel-1))]}")
        fi
    done
    
    if [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        print_warning "No components selected"
        sleep 2
        show_custom_menu
        return
    fi
    
    # Resolve dependencies
    print_step "Resolving dependencies..."
    local original_count=${#SELECTED_COMPONENTS[@]}
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        resolve_dependencies "$comp"
    done
    
    if [ ${#SELECTED_COMPONENTS[@]} -gt "$original_count" ]; then
        print_info "Added $((${#SELECTED_COMPONENTS[@]} - original_count)) dependencies"
    fi
    
    show_installation_preview
}

#############################################################################
# Installation Preview & Confirmation
#############################################################################

show_installation_preview() {
    # Only clear screen in interactive mode
    if [ "$NON_INTERACTIVE" != true ]; then
        clear
    fi
    print_header
    
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  📦 Installation Preview${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # Show installation details
    if [ -n "$PROFILE" ]; then
        local profile_name
        profile_name=$(jq_exec ".profiles.${PROFILE}.name" "$TEMP_DIR/registry.json" 2>/dev/null || echo "$PROFILE")
        echo -e "  ${GREEN}▸${NC} Profile:    ${BOLD}${profile_name}${NC}"
    else
        echo -e "  ${GREEN}▸${NC} Mode:       ${BOLD}Custom${NC}"
    fi
    echo -e "  ${CYAN}▸${NC} Location:   ${INSTALL_DIR}"
    echo -e "  ${MAGENTA}▸${NC} Components: ${BOLD}${#SELECTED_COMPONENTS[@]}${NC} total"
    echo ""
    
    # Group by type with better formatting
    local types=("agent:🤖:Agents" "subagent:🔧:Subagents" "command:⚡:Commands" \
                 "tool:🛠️:Tools" "plugin:🔌:Plugins" "skill:📚:Skills" \
                 "context:📄:Contexts" "config:⚙️:Config")
    
    for type_info in "${types[@]}"; do
        IFS=':' read -r type icon label <<< "$type_info"
        
        # Get components of this type
        local comps=()
        for comp in "${SELECTED_COMPONENTS[@]}"; do
            [ "${comp%%:*}" = "$type" ] && comps+=("${comp##*:}")
        done
        
        [ ${#comps[@]} -eq 0 ] && continue
        
        # Print category header
        echo -e "  ${icon} ${BOLD}${label}${NC} (${#comps[@]})"
        
        # Print components in columns (2 per line)
        local col=0
        for comp in "${comps[@]}"; do
            local name
            name=$(jq_exec ".components.$(get_registry_key "$type")[]? | 
                   select(.id == \"${comp}\" or (.aliases // [] | index(\"${comp}\"))) | 
                   .name" "$TEMP_DIR/registry.json" 2>/dev/null || echo "$comp")
            
            # Skip empty names
            [ -z "$name" ] && continue
            
            if [ $col -eq 0 ]; then
                printf "      • %-35s" "$name"
                col=1
            else
                printf "• %s\n" "$name"
                col=0
            fi
        done
        if [ $col -eq 1 ]; then
            printf "\n"
        fi
        echo ""
    done
    
    echo -e "${CYAN}────────────────────────────────────────${NC}\n"
    
    # Skip confirmation if profile was provided via command line
    if [ "$NON_INTERACTIVE" = true ]; then
        print_info "Installing automatically (profile specified)..."
        perform_installation
    else
        read -r -p "Proceed with installation? [Y/n]: " confirm
        
        if [[ $confirm =~ ^[Nn] ]]; then
            print_info "Installation cancelled"
            cleanup_and_exit 0
        fi
        
        perform_installation
    fi
}

#############################################################################
# Collision Detection
#############################################################################

show_collision_report() {
    local collision_count=$1
    shift
    local collisions=("$@")
    
    echo ""
    print_warning "Found ${collision_count} file collision(s):"
    echo ""
    
    # Group by type
    local agents=()
    local subagents=()
    local commands=()
    local tools=()
    local plugins=()
    local skills=()
    local contexts=()
    local configs=()
    
    for file in "${collisions[@]}"; do
        # Skip empty entries
        [ -z "$file" ] && continue
        
        if [[ $file == *"/agent/subagents/"* ]]; then
            subagents+=("$file")
        elif [[ $file == *"/agent/"* ]]; then
            agents+=("$file")
        elif [[ $file == *"/command/"* ]]; then
            commands+=("$file")
        elif [[ $file == *"/tool/"* ]]; then
            tools+=("$file")
        elif [[ $file == *"/plugin/"* ]]; then
            plugins+=("$file")
        elif [[ $file == *"/skill/"* ]]; then
            skills+=("$file")
        elif [[ $file == *"/context/"* ]]; then
            contexts+=("$file")
        else
            configs+=("$file")
        fi
    done
    
    # Display grouped collisions
    [ ${#agents[@]} -gt 0 ] && echo -e "${YELLOW}  Agents (${#agents[@]}):${NC}" && printf '    %s\n' "${agents[@]}"
    [ ${#subagents[@]} -gt 0 ] && echo -e "${YELLOW}  Subagents (${#subagents[@]}):${NC}" && printf '    %s\n' "${subagents[@]}"
    [ ${#commands[@]} -gt 0 ] && echo -e "${YELLOW}  Commands (${#commands[@]}):${NC}" && printf '    %s\n' "${commands[@]}"
    [ ${#tools[@]} -gt 0 ] && echo -e "${YELLOW}  Tools (${#tools[@]}):${NC}" && printf '    %s\n' "${tools[@]}"
    [ ${#plugins[@]} -gt 0 ] && echo -e "${YELLOW}  Plugins (${#plugins[@]}):${NC}" && printf '    %s\n' "${plugins[@]}"
    [ ${#skills[@]} -gt 0 ] && echo -e "${YELLOW}  Skills (${#skills[@]}):${NC}" && printf '    %s\n' "${skills[@]}"
    [ ${#contexts[@]} -gt 0 ] && echo -e "${YELLOW}  Context (${#contexts[@]}):${NC}" && printf '    %s\n' "${contexts[@]}"
    [ ${#configs[@]} -gt 0 ] && echo -e "${YELLOW}  Config (${#configs[@]}):${NC}" && printf '    %s\n' "${configs[@]}"
    
    echo ""
}

get_install_strategy() {
    echo -e "${BOLD}How would you like to proceed?${NC}\n" >&2
    echo -e "  1) ${GREEN}Skip existing${NC} - Only install new files, keep all existing files unchanged" >&2
    echo -e "  2) ${YELLOW}Overwrite all${NC} - Replace existing files with new versions (your changes will be lost)" >&2
    echo -e "  3) ${CYAN}Backup & overwrite${NC} - Backup existing files, then install new versions" >&2
    echo -e "  4) ${RED}Cancel${NC} - Exit without making changes" >&2
    echo "" >&2
    read -r -p "Enter your choice [1-4]: " strategy_choice
    
    case $strategy_choice in
        1) echo "skip" ;;
        2) 
            echo "" >&2
            print_warning "This will overwrite existing files. Your changes will be lost!"
            read -r -p "Are you sure? Type 'yes' to confirm: " confirm
            if [ "$confirm" = "yes" ]; then
                echo "overwrite"
            else
                echo "cancel"
            fi
            ;;
        3) echo "backup" ;;
        4) echo "cancel" ;;
        *) echo "cancel" ;;
    esac
}

#############################################################################
# Installation
#############################################################################

perform_installation() {
    print_step "Preparing installation..."
    
    # Create base directory only - subdirectories created on-demand when files are installed
    mkdir -p "$INSTALL_DIR"
    
    # Check for collisions
    local collisions=()
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        local type="${comp%%:*}"
        local id="${comp##*:}"
        local registry_key
        registry_key=$(get_registry_key "$type")
        local path
        path=$(resolve_component_path "$type" "$id")
        
        if [ -n "$path" ] && [ "$path" != "null" ]; then
            local install_path
            install_path=$(get_install_path "$path")
            if [ -f "$install_path" ]; then
                collisions+=("$install_path")
            fi
        fi
    done
    
    # Determine installation strategy
    local install_strategy="fresh"
    
    if [ ${#collisions[@]} -gt 0 ]; then
        # In non-interactive mode, use default strategy (skip existing files)
        if [ "$NON_INTERACTIVE" = true ]; then
            print_info "Found ${#collisions[@]} existing file(s) - using 'skip' strategy (non-interactive mode)"
            print_info "To overwrite, download script and run interactively, or delete existing files first"
            install_strategy="skip"
        else
            show_collision_report ${#collisions[@]} "${collisions[@]}"
            install_strategy=$(get_install_strategy)
            
            if [ "$install_strategy" = "cancel" ]; then
                print_info "Installation cancelled by user"
                cleanup_and_exit 0
            fi
        fi
        
        # Handle backup strategy
        if [ "$install_strategy" = "backup" ]; then
            local backup_dir
            backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d-%H%M%S)"
            print_step "Creating backup..."
            
            # Only backup files that will be overwritten
            local backup_count=0
            for file in "${collisions[@]}"; do
                if [ -f "$file" ]; then
                    local backup_file="${backup_dir}/${file}"
                    mkdir -p "$(dirname "$backup_file")"
                    if cp "$file" "$backup_file" 2>/dev/null; then
                        backup_count=$((backup_count + 1))
                    else
                        print_warning "Failed to backup: $file"
                    fi
                fi
            done
            
            if [ $backup_count -gt 0 ]; then
                print_success "Backed up ${backup_count} file(s) to $backup_dir"
                install_strategy="overwrite"  # Now we can overwrite
            else
                print_error "Backup failed. Installation cancelled."
                cleanup_and_exit 1
            fi
        fi
    fi
    
    # Perform installation
    print_step "Installing components..."
    
    local installed=0
    local skipped=0
    local failed=0
    
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        local type="${comp%%:*}"
        local id="${comp##*:}"
        
        # Get the correct registry key (handles singular/plural)
        local registry_key
        registry_key=$(get_registry_key "$type")
        
        # Get component path
        local path
        path=$(resolve_component_path "$type" "$id")
        
        if [ -z "$path" ] || [ "$path" = "null" ]; then
            print_warning "Could not find path for ${comp}"
            failed=$((failed + 1))
            continue
        fi
        
        # Check if component has additional files (for skills)
        local files_array
        files_array=$(jq_exec ".components.${registry_key}[]? | select(.id == \"${id}\") | .files[]?" "$TEMP_DIR/registry.json")
        
        if [ -n "$files_array" ]; then
            # Component has multiple files - download all of them
            local component_installed=0
            local component_failed=0
            
            while IFS= read -r file_path; do
                [ -z "$file_path" ] && continue
                
                local dest
                dest=$(get_install_path "$file_path")
                
                # Check if file exists and we're in skip mode
                if [ -f "$dest" ] && [ "$install_strategy" = "skip" ]; then
                    continue
                fi
                
                # Download file
                local url="${RAW_URL}/${file_path}"
                mkdir -p "$(dirname "$dest")"
                
                if curl -fsSL "$url" -o "$dest"; then
                    # Transform paths for global installation
                    if [[ "$INSTALL_DIR" != ".opencode" ]] && [[ "$INSTALL_DIR" != *"/.opencode" ]]; then
                        local expanded_path="${INSTALL_DIR/#\~/$HOME}"
                        sed -i.bak -e "s|@\.opencode/context/|@${expanded_path}/context/|g" \
                                   -e "s|\.opencode/context|${expanded_path}/context|g" "$dest" 2>/dev/null || true
                        rm -f "${dest}.bak" 2>/dev/null || true
                    fi
                    component_installed=$((component_installed + 1))
                else
                    component_failed=$((component_failed + 1))
                fi
            done <<< "$files_array"
            
            if [ $component_failed -eq 0 ]; then
                print_success "Installed ${type}: ${id} (${component_installed} files)"
                installed=$((installed + 1))
            else
                print_error "Failed to install ${type}: ${id} (${component_failed} files failed)"
                failed=$((failed + 1))
            fi
        else
            # Single file component - original logic
            local dest
            dest=$(get_install_path "$path")
            
            # Check if file exists before we install (for proper messaging)
            local file_existed=false
            if [ -f "$dest" ]; then
                file_existed=true
            fi
            
            # Check if file exists and we're in skip mode
            if [ "$file_existed" = true ] && [ "$install_strategy" = "skip" ]; then
                print_info "Skipped existing: ${type}:${id}"
                skipped=$((skipped + 1))
                continue
            fi
            
            # Download component
            local url="${RAW_URL}/${path}"
            
            # Create parent directory if needed
            mkdir -p "$(dirname "$dest")"
            
            if curl -fsSL "$url" -o "$dest"; then
                # Transform paths for global installation (any non-local path)
                # Local paths: .opencode or */.opencode
                if [[ "$INSTALL_DIR" != ".opencode" ]] && [[ "$INSTALL_DIR" != *"/.opencode" ]]; then
                    # Expand tilde and get absolute path for transformation
                    local expanded_path="${INSTALL_DIR/#\~/$HOME}"
                    # Transform @.opencode/context/ references to actual install path
                    sed -i.bak -e "s|@\.opencode/context/|@${expanded_path}/context/|g" \
                               -e "s|\.opencode/context|${expanded_path}/context|g" "$dest" 2>/dev/null || true
                    rm -f "${dest}.bak" 2>/dev/null || true
                fi
                
                # Show appropriate message based on whether file existed before
                if [ "$file_existed" = true ]; then
                    print_success "Updated ${type}: ${id}"
                else
                    print_success "Installed ${type}: ${id}"
                fi
                installed=$((installed + 1))
            else
                print_error "Failed to install ${type}: ${id}"
                failed=$((failed + 1))
            fi
        fi
    done
    
    # Handle additional paths for advanced profile
    if [ "$PROFILE" = "advanced" ]; then
        local additional_paths
        additional_paths=$(jq_exec '.profiles.advanced.additionalPaths[]?' "$TEMP_DIR/registry.json")
        if [ -n "$additional_paths" ]; then
            print_step "Installing additional paths..."
            while IFS= read -r path; do
                # For directories, we'd need to recursively download
                # For now, just note them
                print_info "Additional path: $path (manual download required)"
            done <<< "$additional_paths"
        fi
    fi
    
    echo ""
    print_success "Installation complete!"
    echo -e "  Installed: ${GREEN}${installed}${NC}"
    [ $skipped -gt 0 ] && echo -e "  Skipped: ${CYAN}${skipped}${NC}"
    [ $failed -gt 0 ] && echo -e "  Failed: ${RED}${failed}${NC}"
    
    show_post_install
}

#############################################################################
# Post-Installation
#############################################################################

show_agent_model_recommendations() {
    print_step "Agent Model Recommendations"

    fetch_latest_models

    # Only show if providers are configured AND models were accepted
    if [ "$CONNECTED_PROVIDERS_CONFIGURED" = false ]; then
        echo -e "To get the best experience with your installed agents:${NC}\n"
        
        echo -e "${YELLOW}Option 1: Connect AI Providers${NC}"
        echo "  Configure providers to access premium models:"
        echo "    • Claude (Anthropic)"
        echo "    • OpenAI (GPT models)"
        echo "    • Opencode-zen"
        echo "    • Google Gemini"
        echo ""
        echo "  Run the installer again and choose 'Yes' when asked about providers."
        echo ""
        
        echo -e "${GREEN}Option 2: Use Free Models${NC}"
        echo "  Start immediately with these free models:"
        for model in "${FREE_MODELS[@]}"; do
            echo "    • $model"
        done
        echo ""
        echo "  These models work without any provider configuration!"
        echo ""
        
        return
    fi
    
    # Check if SELECTED_COMPONENTS is available and populated
    if [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        print_info "No components were selected for installation."
        print_info "Run the installer again to select components."
        echo ""
        return
    fi
    
    echo -e "${BOLD}Based on your installed agents and configured providers:${NC}\n"
    
    # Build list of installed agents from SELECTED_COMPONENTS
    local installed_agents=()
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        local type="${comp%%:*}"
        if [ "$type" = "agent" ]; then
            local id="${comp##*:}"
            installed_agents+=("$id")
        fi
    done
    
    # If no agents installed, skip
    if [ ${#installed_agents[@]} -eq 0 ]; then
        return
    fi
    
    # For each installed agent, fetch model recommendations and verify against LATEST_MODELS
    for agent_id in "${installed_agents[@]}"; do
        # Get agent name and model recommendations from registry
        local agent_name
        agent_name=$(jq_exec ".components.agents[]? | select(.id == \"${agent_id}\") | .name" "$TEMP_DIR/registry.json")
        
        # Get model recommendations object
        local recommendations
        recommendations=$(jq_exec ".components.agents[]? | select(.id == \"${agent_id}\") | .\"model-recommendation\"" "$TEMP_DIR/registry.json")
        
        # Skip if no recommendations or empty object
        if [ -z "$recommendations" ] || [ "$recommendations" = "{}" ] || [ "$recommendations" = "null" ]; then
            continue
        fi
        
        # Extract recommendations for each configured provider
        local has_valid_rec=false
        local rec_text=""
        
        # Claude
        if [ "$PROVIDER_CLAUDE" = true ]; then
            local claude_model
            claude_model=$(echo "$recommendations" | jq_exec '.claude // empty')
            if [ -n "$claude_model" ] && [ "$claude_model" != "null" ]; then
                # Verify against LATEST_MODELS
                local provider="${claude_model%%/*}"
                local model_id="${claude_model##*/}"
                if model_exists "$provider" "$model_id"; then
                    rec_text="${rec_text}    ${CYAN}Claude:${NC} ${claude_model}\n"
                    has_valid_rec=true
                fi
            fi
        fi
        
        # OpenAI
        if [ "$PROVIDER_OPENAI" = true ]; then
            local openai_model
            openai_model=$(echo "$recommendations" | jq_exec '.openai // empty')
            if [ -n "$openai_model" ] && [ "$openai_model" != "null" ]; then
                local provider="${openai_model%%/*}"
                local model_id="${openai_model##*/}"
                if model_exists "$provider" "$model_id"; then
                    rec_text="${rec_text}    ${CYAN}OpenAI:${NC} ${openai_model}\n"
                    has_valid_rec=true
                fi
            fi
        fi
        
        # Opencode-zen
        if [ "$PROVIDER_OPENCODE_ZEN" = true ]; then
            local opencode_model
            opencode_model=$(echo "$recommendations" | jq_exec '.["opencode-zen"] // empty')
            if [ -n "$opencode_model" ] && [ "$opencode_model" != "null" ]; then
                local provider="${opencode_model%%/*}"
                local model_id="${opencode_model##*/}"
                if model_exists "$provider" "$model_id"; then
                    rec_text="${rec_text}    ${CYAN}Opencode-zen:${NC} ${opencode_model}\n"
                    has_valid_rec=true
                fi
            fi
        fi
        
        # Google Gemini
        if [ "$PROVIDER_GOOGLE_GEMINI" = true ]; then
            local google_model
            google_model=$(echo "$recommendations" | jq_exec '.google // empty')
            if [ -n "$google_model" ] && [ "$google_model" != "null" ]; then
                local provider="${google_model%%/*}"
                local model_id="${google_model##*/}"
                if model_exists "$provider" "$model_id"; then
                    rec_text="${rec_text}    ${CYAN}Google:${NC} ${google_model}\n"
                    has_valid_rec=true
                fi
            fi
        fi
        
        # Only print if we have valid recommendations
        if [ "$has_valid_rec" = true ]; then
            echo -e "  ${GREEN}${agent_name}${NC} (${agent_id})"
            echo -e "$rec_text"
        fi
    done
    
    echo ""
}

show_post_install() {
    echo ""
    show_agent_model_recommendations
    
    print_step "Next Steps"
    
    echo -e "1. Review the installed components in ${CYAN}${INSTALL_DIR}/${NC}"

    # Check if env.example was installed
    if [ -f "${INSTALL_DIR}/env.example" ] || [ -f "env.example" ]; then
        echo -e "2. Copy env.example to .env and configure:"
        echo -e "   ${CYAN}cp env.example .env${NC}"
        echo -e "3. Start using OpenCode agents:"
    else
        echo -e "2. Start using OpenCode agents:"
    fi
    echo -e "   ${CYAN}opencode${NC}"
    echo ""
    
    # Show installation location info
    print_info "Installation directory: ${CYAN}${INSTALL_DIR}${NC}"
    
    # Check for backup directories
    local has_backup=0
    local backup_dir
    local backup_dirs=()

    shopt -s nullglob
    backup_dirs=("${INSTALL_DIR}.backup."*)
    shopt -u nullglob

    for backup_dir in "${backup_dirs[@]}"; do
        if [ -d "$backup_dir" ]; then
            has_backup=1
            break
        fi
    done
    if [ "$has_backup" -eq 1 ]; then
        print_info "Backup created - you can restore files from ${INSTALL_DIR}.backup.* if needed"
    fi
    
    print_info "Documentation: ${REPO_URL}"
    echo ""
    
    cleanup_and_exit 0
}

#############################################################################
# Component Listing
#############################################################################

list_components() {
    clear || true
    print_header
    
    echo -e "${BOLD}Available Components${NC}\n"
    
    local categories=("agents" "subagents" "commands" "tools" "plugins" "skills" "contexts")
    
    for category in "${categories[@]}"; do
        local cat_display
        cat_display=$(echo "$category" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
        echo -e "${CYAN}${BOLD}${cat_display}:${NC}"
        
        local components
        components=$(jq_exec ".components.${category}[]? | \"\(.id)|\(.name)|\(.description)\"" "$TEMP_DIR/registry.json")
        
        while IFS='|' read -r id name desc; do
            echo -e "  ${GREEN}${name}${NC} (${id})"
            echo -e "    ${desc}"
        done <<< "$components"
        
        echo ""
    done
}

#############################################################################
# Cleanup
#############################################################################

cleanup_and_exit() {
    rm -rf "$TEMP_DIR"
    exit "$1"
}

trap 'cleanup_and_exit 1' INT TERM

#############################################################################
# Main
#############################################################################

main() {
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --install-dir=*)
                CUSTOM_INSTALL_DIR="${1#*=}"
                # Basic validation - check not empty
                if [ -z "$CUSTOM_INSTALL_DIR" ]; then
                    echo "Error: --install-dir requires a non-empty path"
                    exit 1
                fi
                shift
                ;;
            --install-dir)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    CUSTOM_INSTALL_DIR="$2"
                    shift 2
                else
                    echo "Error: --install-dir requires a path argument"
                    exit 1
                fi
                ;;
            minimalCoder|--minimalCoder)
                INSTALL_MODE="profile"
                PROFILE="minimalCoder"
                NON_INTERACTIVE=true
                shift
                ;;
            standardCoder|--standardCoder)
                INSTALL_MODE="profile"
                PROFILE="standardCoder"
                NON_INTERACTIVE=true
                shift
                ;;
            extendedCoder|--extendedCoder)
                INSTALL_MODE="profile"
                PROFILE="extendedCoder"
                NON_INTERACTIVE=true
                shift
                ;;
            advanced|--advanced)
                INSTALL_MODE="profile"
                PROFILE="advanced"
                NON_INTERACTIVE=true
                shift
                ;;
            list|--list)
                check_dependencies
                fetch_registry
                list_components
                cleanup_and_exit 0
                ;;
            --help|-h|help)
                print_header
                echo "Usage: $0 [PROFILE] [OPTIONS]"
                echo ""
                echo -e "${BOLD}Profiles:${NC}"
                echo "  minimalCoder, --minimalCoder    Minimal setup with core agents"
                echo "  standardCoder, --standardCoder    Code-focused development tools"
                echo "  extendedCoder, --extendedCoder    Everything except system-builder"
                echo "  advanced, --advanced      Complete system with all components"
                echo ""
                echo -e "${BOLD}Options:${NC}"
                echo "  --install-dir PATH        Custom installation directory"
                echo "                            (default: .opencode)"
                echo "  list, --list              List all available components"
                echo "  help, --help, -h          Show this help message"
                echo ""
                echo -e "${BOLD}Environment Variables:${NC}"
                echo "  OPENCODE_INSTALL_DIR      Installation directory"
                echo "  OPENCODE_BRANCH           Git branch to install from (default: main)"
                echo ""
                echo -e "${BOLD}Examples:${NC}"
                echo ""
                echo "  ${CYAN}# Interactive mode (choose location and components)${NC}"
                echo "  $0"
                echo ""
                echo "  ${CYAN}# Quick install with default location (.opencode/)${NC}"
                echo "  $0 standardCoder"
                echo ""
                echo "  ${CYAN}# Install to global location (Linux/macOS)${NC}"
                echo "  $0 standardCoder --install-dir ~/.config/opencode"
                echo ""
                echo "  ${CYAN}# Install to global location (Windows Git Bash)${NC}"
                echo "  $0 standardCoder --install-dir ~/.config/opencode"
                echo ""
                echo "  ${CYAN}# Install to custom location${NC}"
                echo "  $0 standardCoder --install-dir ~/my-agents"
                echo ""
                echo "  ${CYAN}# Using environment variable${NC}"
                echo "  export OPENCODE_INSTALL_DIR=~/.config/opencode"
                echo "  $0 developer"
                echo ""
                echo "  ${CYAN}# Install from URL (non-interactive)${NC}"
                echo "  curl -fsSL https://raw.githubusercontent.com/sina96/OpenCoderAgent-slim/main/install.sh | bash -s standardCoder"
                echo ""
                echo -e "${BOLD}Platform Support:${NC}"
                echo "  ✓ Linux (bash 3.2+)"
                echo "  ✓ macOS (bash 3.2+)"
                echo "  ✓ Windows (Git Bash, WSL)"
                echo ""
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done
    
    # Apply custom install directory if specified (CLI arg overrides env var)
    if [ -n "$CUSTOM_INSTALL_DIR" ]; then
        local normalized_path
        if normalize_and_validate_path "$CUSTOM_INSTALL_DIR" > /dev/null; then
            normalized_path=$(normalize_and_validate_path "$CUSTOM_INSTALL_DIR")
            INSTALL_DIR="$normalized_path"
            if ! validate_install_path "$INSTALL_DIR"; then
                print_warning "Installation path may have issues, but continuing..."
            fi
        else
            print_error "Invalid installation directory: $CUSTOM_INSTALL_DIR"
            exit 1
        fi
    fi
    
    check_bash_version
    check_dependencies
    fetch_registry
    
    # Show connected providers configuration (first step)
    show_connected_providers_menu

    if [ -n "$PROFILE" ]; then
        # Non-interactive mode (compatible with bash 3.2+)
        SELECTED_COMPONENTS=()
        local temp_file="$TEMP_DIR/components.tmp"
        get_profile_components "$PROFILE" > "$temp_file"
        while IFS= read -r component; do
            [ -n "$component" ] && SELECTED_COMPONENTS+=("$component")
        done < "$temp_file"

        expand_selected_components

        # Resolve dependencies for profile installs
        print_step "Resolving dependencies..."
        local original_count=${#SELECTED_COMPONENTS[@]}
        for comp in "${SELECTED_COMPONENTS[@]}"; do
            resolve_dependencies "$comp"
        done

        local new_count=${#SELECTED_COMPONENTS[@]}
        if [ "$new_count" -gt "$original_count" ]; then
            local added=$((new_count - original_count))
            print_info "Added $added dependencies"
        fi

        show_installation_preview
    else
        # Interactive mode - show location menu first
        show_install_location_menu
        show_main_menu
        
        if [ "$INSTALL_MODE" = "profile" ]; then
            show_profile_menu
        elif [ "$INSTALL_MODE" = "custom" ]; then
            show_custom_menu
        fi
    fi
}

main "$@"
