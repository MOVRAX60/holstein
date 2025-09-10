#!/bin/bash

# =============================================================================
# LINE ENDINGS FIX SCRIPT
# =============================================================================
# Fixes Windows line endings (CRLF) to Unix line endings (LF)
# Solves the "bad interpreter: No such file or directory" error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔧 Fixing Windows Line Endings"
echo "==============================="
echo "Converting CRLF → LF for all script files..."
echo

# Method 1: Using dos2unix (if available)
fix_with_dos2unix() {
    if command -v dos2unix >/dev/null 2>&1; then
        echo "✅ Using dos2unix command..."

        # Fix all shell scripts
        find "$PROJECT_DIR" -name "*.sh" -type f -exec dos2unix {} \; 2>/dev/null

        # Fix other text files that might have the issue
        find "$PROJECT_DIR" -name "*.py" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name "*.yml" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name "*.yaml" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name "*.json" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name "*.md" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name "*.txt" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name ".env*" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name "Makefile" -type f -exec dos2unix {} \; 2>/dev/null
        find "$PROJECT_DIR" -name "Dockerfile*" -type f -exec dos2unix {} \; 2>/dev/null

        echo "✅ dos2unix conversion completed"
        return 0
    else
        echo "⚠️  dos2unix not available, trying alternative method..."
        return 1
    fi
}

# Method 2: Using sed (universal)
fix_with_sed() {
    echo "✅ Using sed command..."

    # Function to fix a single file
    fix_file() {
        local file="$1"
        if [[ -f "$file" ]]; then
            # Check if file has Windows line endings
            if grep -q $'\r' "$file" 2>/dev/null; then
                echo "  Fixing: $file"
                sed -i 's/\r$//' "$file"
            fi
        fi
    }

    # Fix all shell scripts
    find "$PROJECT_DIR" -name "*.sh" -type f | while read -r file; do
        fix_file "$file"
    done

    # Fix other important files
    find "$PROJECT_DIR" -name "*.py" -type f | while read -r file; do
        fix_file "$file"
    done

    find "$PROJECT_DIR" -name "*.yml" -type f | while read -r file; do
        fix_file "$file"
    done

    find "$PROJECT_DIR" -name "*.yaml" -type f | while read -r file; do
        fix_file "$file"
    done

    find "$PROJECT_DIR" -name "*.md" -type f | while read -r file; do
        fix_file "$file"
    done

    # Fix specific important files
    for file in "$PROJECT_DIR/setup.sh" "$PROJECT_DIR/Makefile" "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.example"; do
        fix_file "$file"
    done

    echo "✅ sed conversion completed"
}

# Method 3: Using tr (alternative)
fix_with_tr() {
    echo "✅ Using tr command as backup..."

    find "$PROJECT_DIR" -name "*.sh" -type f | while read -r file; do
        if [[ -f "$file" ]]; then
            echo "  Fixing: $file"
            tr -d '\r' < "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        fi
    done

    echo "✅ tr conversion completed"
}

# Main execution
main() {
    echo "📁 Project directory: $PROJECT_DIR"
    echo "🔍 Scanning for files with Windows line endings..."
    echo

    # Count files with Windows line endings
    local files_with_crlf=0
    while IFS= read -r -d '' file; do
        if grep -q $'\r' "$file" 2>/dev/null; then
            ((files_with_crlf++))
            echo "❌ Found CRLF in: $file"
        fi
    done < <(find "$PROJECT_DIR" -name "*.sh" -o -name "*.py" -o -name "*.yml" -o -name "*.yaml" -o -name "setup.sh" -o -name "Makefile" -print0)

    if [[ $files_with_crlf -eq 0 ]]; then
        echo "✅ No Windows line ending issues found!"
        exit 0
    fi

    echo
    echo "🔧 Found $files_with_crlf files with Windows line endings"
    echo "🔄 Converting to Unix line endings..."
    echo

    # Try different methods in order of preference
    if fix_with_dos2unix; then
        echo "✅ Conversion successful using dos2unix"
    elif fix_with_sed; then
        echo "✅ Conversion successful using sed"
    else
        fix_with_tr
        echo "✅ Conversion successful using tr"
    fi

    # Fix permissions after conversion
    echo
    echo "🔒 Fixing script permissions..."
    find "$PROJECT_DIR" -name "*.sh" -type f -exec chmod +x {} \;
    chmod +x "$PROJECT_DIR/setup.sh" 2>/dev/null || true

    echo "✅ Script permissions fixed"
    echo
    echo "🎉 Line ending conversion completed!"
    echo
    echo "📋 Next steps:"
    echo "   1. Try running your script again: ./setup.sh"
    echo "   2. If you're using Git, consider configuring it to handle line endings:"
    echo "      git config core.autocrlf input"
    echo "      git config core.eol lf"
    echo
}

# Install dos2unix if not available (optional)
install_dos2unix() {
    echo "📦 Installing dos2unix..."

    if command -v yum >/dev/null 2>&1; then
        echo "Using yum to install dos2unix..."
        sudo yum install -y dos2unix
    elif command -v dnf >/dev/null 2>&1; then
        echo "Using dnf to install dos2unix..."
        sudo dnf install -y dos2unix
    elif command -v apt-get >/dev/null 2>&1; then
        echo "Using apt-get to install dos2unix..."
        sudo apt-get update && sudo apt-get install -y dos2unix
    else
        echo "⚠️  Cannot automatically install dos2unix"
        echo "   Please install it manually or the script will use sed/tr"
    fi
}

# Check if user wants to install dos2unix
if [[ "${1:-}" == "--install-dos2unix" ]]; then
    install_dos2unix
    exit 0
fi

# Run main function
main "$@"