#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Intel Corporation
# All rights reserved.

# =============================================================================
# ShellCheck Scanner for Edge GFX Linux Installer
# 
# This script scans the entire edge-gfx-linux-installer directory for shell scripts
# and runs shellcheck on each one to identify potential issues.
# =============================================================================

set -euo pipefail

# Script directory (should be run from edge-gfx-linux-installer root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$SCRIPT_DIR"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Counters
SCRIPTS_FOUND=0
SCRIPTS_PASSED=0
SCRIPTS_FAILED=0
SCRIPTS_WITH_WARNINGS=0

# Array to track processed scripts
declare -a CHECKED_SCRIPTS

# Arrays to track failed scripts and their errors
declare -a FAILED_SCRIPTS
declare -a FAILED_SCRIPTS_ERRORS

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO")  printf "${BLUE}[INFO ]${NC} %s\n" "$message" ;;
        "WARN")  printf "${YELLOW}[WARN ]${NC} %s\n" "$message" ;;
        "ERROR") printf "${RED}[ERROR]${NC} %s\n" "$message" ;;
        "SUCCESS") printf "${GREEN}[SUCCESS]${NC} %s\n" "$message" ;;
        "STEP")  printf "${BOLD}[STEP ]${NC} %s\n" "$message" ;;
    esac
}

check_script() {
    local script_path="$1"
    local relative_path
    relative_path="$(realpath --relative-to="$TOOLKIT_ROOT" "$script_path")"
    
    # Track this script
    CHECKED_SCRIPTS+=("$relative_path")
    
    printf "\\n"
    log "STEP" "Checking: $relative_path"
    
    # Run shellcheck on the script
    local shellcheck_output=""
    local exit_code=0
    
    if shellcheck_output=$(shellcheck -x "$script_path" 2>&1); then
        if [[ -n "$shellcheck_output" ]]; then
            # Has warnings but no errors
            log "WARN" "Warnings found:"
            printf "%s\\n" "$shellcheck_output"
            SCRIPTS_WITH_WARNINGS=$((SCRIPTS_WITH_WARNINGS + 1))
        else
            # Clean, no issues
            log "SUCCESS" "No issues found"
            SCRIPTS_PASSED=$((SCRIPTS_PASSED + 1))
        fi
    else
        # Has errors
        exit_code=$?
        log "ERROR" "Issues found (exit code: $exit_code):"
        printf "%s\\n" "$shellcheck_output"
        SCRIPTS_FAILED=$((SCRIPTS_FAILED + 1))
        
        # Store failure details for summary
        FAILED_SCRIPTS+=("$relative_path")
        FAILED_SCRIPTS_ERRORS+=("$shellcheck_output")
    fi
}

scan_directory() {
    local scan_dir="$1"
    
    log "INFO" "Scanning directory: $(realpath --relative-to="$TOOLKIT_ROOT" "$scan_dir")"
    
    # Find shell scripts and process them
    local -a script_files=()
    
    # Find .sh files only
    while IFS= read -r -d '' file; do
        script_files+=("$file")
    done < <(find "$scan_dir" -name "*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${#script_files[@]} -eq 0 ]]; then
        log "WARN" "No shell scripts found in $(realpath --relative-to="$TOOLKIT_ROOT" "$scan_dir")"
        return 0
    fi
    
    log "INFO" "Found ${#script_files[@]} shell script(s)"
    
    # Check each script
    for script in "${script_files[@]}"; do
        SCRIPTS_FOUND=$((SCRIPTS_FOUND + 1))
        check_script "$script"
    done
}

print_summary() {
    local summary_file
    local scan_date
    local scan_target_rel
    summary_file="shellcheck-summary-$(date +%Y%m%d-%H%M%S).txt"
    scan_date=$(date "+%Y-%m-%d %H:%M:%S")
    scan_target_rel="$(realpath --relative-to="$TOOLKIT_ROOT" "${scan_target:-$TOOLKIT_ROOT}")"
    
    # Console output (clean and simple)
    printf "\\n"
    printf "=======================================================================\\n"
    log "INFO" "ShellCheck Summary"
    printf "=======================================================================\\n"
    printf "Scripts found:         %d\\n" "$SCRIPTS_FOUND"
    printf "Scripts passed:        %d\\n" "$SCRIPTS_PASSED"
    printf "Scripts with warnings: %d\\n" "$SCRIPTS_WITH_WARNINGS"
    printf "Scripts failed:        %d\\n" "$SCRIPTS_FAILED"
    printf "\\n"
    
    # Create detailed file output
    {
        printf "================================================================================\\n"
        printf "                        SHELLCHECK ANALYSIS REPORT\\n"
        printf "                       Edge GFX Linux Installer Scanner\\n"
        printf "================================================================================\\n"
        printf "\\n"
        printf "SCAN INFORMATION:\\n"
        printf "  Date & Time    : %s\\n" "$scan_date"
        printf "  Scan Target    : %s\\n" "$scan_target_rel"
        printf "  Toolkit Root   : %s\\n" "$TOOLKIT_ROOT"
        printf "  Report File    : %s\\n" "$summary_file"
        printf "\\n"
        printf "ANALYSIS RESULTS:\\n"
        printf "  Scripts found         : %d\\n" "$SCRIPTS_FOUND"
        printf "  Scripts passed        : %d\\n" "$SCRIPTS_PASSED"
        printf "  Scripts with warnings : %d\\n" "$SCRIPTS_WITH_WARNINGS"
        printf "  Scripts failed        : %d\\n" "$SCRIPTS_FAILED"
        printf "\\n"
    } > "$summary_file"
    
    if [[ $SCRIPTS_FAILED -eq 0 && $SCRIPTS_WITH_WARNINGS -eq 0 ]]; then
        log "SUCCESS" "All scripts passed shellcheck without issues!"
        if [[ ${#CHECKED_SCRIPTS[@]} -gt 0 ]]; then
            printf "\\nNo issues found in the following scripts:\\n"
            {
                printf "STATUS: SUCCESS - All scripts passed without issues!\\n"
                printf "\\n"
                printf "CLEAN SCRIPTS:\\n"
            } >> "$summary_file"
            for script in "${CHECKED_SCRIPTS[@]}"; do
                printf "  ✓ %s\\n" "$script"
                printf "  ✓ %s\\n" "$script" >> "$summary_file"
            done
        else
            printf "STATUS: SUCCESS - All scripts passed without issues!\\n" >> "$summary_file"
        fi
        printf "\\n📄 Summary saved to: %s\\n" "$summary_file"
        log "INFO" "Summary saved to: $summary_file"
        return 0
        
    elif [[ $SCRIPTS_FAILED -eq 0 ]]; then
        log "WARN" "All scripts passed but some have warnings"
        printf "STATUS: PASSED WITH WARNINGS - Please review warnings above\\n" >> "$summary_file"
        printf "\\n📄 Summary saved to: %s\\n" "$summary_file"
        log "INFO" "Summary saved to: $summary_file"
        return 0
        
    else
        log "ERROR" "$SCRIPTS_FAILED script(s) failed shellcheck"
        {
            printf "STATUS: FAILED - %d script(s) failed shellcheck\\n" "$SCRIPTS_FAILED"
            printf "\\n"
        } >> "$summary_file"
        
        # Include failure details in the summary file
        if [[ ${#FAILED_SCRIPTS[@]} -gt 0 ]]; then
            printf "\\nDetailed failure information:\\n"
            printf "DETAILED FAILURE ANALYSIS:\\n" >> "$summary_file"
            printf "================================================================================\\n" >> "$summary_file"
            for ((i=0; i<${#FAILED_SCRIPTS[@]}; i++)); do
                printf "\\nFailed script: %s\\n" "${FAILED_SCRIPTS[i]}"
                printf "Error details:\\n%s\\n" "${FAILED_SCRIPTS_ERRORS[i]}"
                {
                    printf "\n"
                    printf "FAILED SCRIPT #%d: %s\n" "$((i+1))" "${FAILED_SCRIPTS[i]}"
                    printf "ERROR DETAILS:\n%s\n" "${FAILED_SCRIPTS_ERRORS[i]}"
                    printf -- "--------------------------------------------------------------------------------\n"
                } >> "$summary_file"
            done
        fi
        
        printf "\\n📄 Summary saved to: %s\\n" "$summary_file"
        log "INFO" "Summary saved to: $summary_file"
        return 1
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [DIRECTORY]

Scan shell scripts in the Edge GFX Linux Installer for shellcheck issues

OPTIONS:
  -h, --help        Show this help message

DIRECTORY:
  Optional directory to scan (default: entire toolkit)

Examples:
  $0                    # Scan entire toolkit
  $0 installer/         # Scan only installer directory
  $0 scripts/           # Scan only scripts directory
EOF
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    local scan_target="$TOOLKIT_ROOT"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                # Directory argument
                if [[ -d "$1" ]]; then
                    scan_target="$(realpath "$1")"
                else
                    log "ERROR" "Directory not found: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check if shellcheck is installed
    if ! command -v shellcheck >/dev/null 2>&1; then
        log "ERROR" "shellcheck is not installed"
        sudo apt install -y shellcheck
        exit 1
    fi
    
    log "INFO" "Starting shellcheck scan of Edge GFX Linux Installer"
    log "INFO" "Toolkit root: $TOOLKIT_ROOT"
    log "INFO" "Scan target: $(realpath --relative-to="$TOOLKIT_ROOT" "$scan_target")"
    
    # Scan the specified directory
    scan_directory "$scan_target"
    
    # Print summary and exit with appropriate code
    print_summary
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Check if shellcheck is available before starting
if ! command -v shellcheck >/dev/null 2>&1; then
    printf "Error: shellcheck is not installed\\n"
    sudo apt install -y shellcheck
    exit 1
fi

main "$@"