#!/bin/bash

# Script to enable/disable and verify debug loggers in jfconfig container
# Usage: ./manage_jfconfig_loggers.sh <enable|disable> <pod-name> <namespace> [container-name]
# Example: ./manage_jfconfig_loggers.sh enable jfrog-artifactory-0 sureshv jfconfig

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check arguments
if [ $# -lt 3 ]; then
    print_error "Usage: $0 <enable|disable> <pod-name> <namespace> [container-name]"
    print_info "Example: $0 enable jfrog-artifactory-0 sureshv jfconfig"
    exit 1
fi

ACTION=$1
POD_NAME=$2
NAMESPACE=$3
CONTAINER_NAME=${4:-jfconfig}
LOGBACK_INCLUDE_FILE="/opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml"

# Validate action
if [ "$ACTION" != "enable" ] && [ "$ACTION" != "disable" ]; then
    print_error "Action must be 'enable' or 'disable'"
    exit 1
fi

# Logger definitions
LOGGER1='<logger name="org.springframework" level="DEBUG"/>'
LOGGER2='<logger name="com.jfrog.jfconfig" level="DEBUG"/>'
LOGGER3='<logger name="org.jfrog.jfconfig" level="DEBUG"/>'

print_info "Managing loggers in pod: $POD_NAME, namespace: $NAMESPACE, container: $CONTAINER_NAME"
print_info "Action: $ACTION"
print_info "Target file: $LOGBACK_INCLUDE_FILE"

# Verify pod exists
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    print_error "Pod $POD_NAME not found in namespace $NAMESPACE"
    exit 1
fi

# Verify container exists in pod
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' | grep -q "$CONTAINER_NAME"; then
    print_error "Container $CONTAINER_NAME not found in pod $POD_NAME"
    exit 1
fi

# Function to check if loggers are present
check_loggers() {
    local content
    content=$(kubectl exec "$POD_NAME" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- cat "$LOGBACK_INCLUDE_FILE" 2>/dev/null || echo "")
    
    if echo "$content" | grep -q "org.springframework.*DEBUG"; then
        return 0  # Loggers found
    else
        return 1  # Loggers not found
    fi
}

# Function to verify loggers
verify_loggers() {
    print_info "Verifying loggers in $LOGBACK_INCLUDE_FILE..."
    
    local content
    content=$(kubectl exec "$POD_NAME" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- cat "$LOGBACK_INCLUDE_FILE" 2>/dev/null)
    
    if [ -z "$content" ]; then
        print_error "Failed to read $LOGBACK_INCLUDE_FILE"
        return 1
    fi
    
    echo ""
    print_info "Current content of $LOGBACK_INCLUDE_FILE:"
    echo "----------------------------------------"
    echo "$content"
    echo "----------------------------------------"
    echo ""
    
    local found_count=0
    if echo "$content" | grep -q "org.springframework.*DEBUG"; then
        print_info "✓ Logger 'org.springframework' (DEBUG) found"
        found_count=$((found_count + 1))
    else
        print_warning "✗ Logger 'org.springframework' (DEBUG) not found"
    fi
    
    if echo "$content" | grep -q "com.jfrog.jfconfig.*DEBUG"; then
        print_info "✓ Logger 'com.jfrog.jfconfig' (DEBUG) found"
        found_count=$((found_count + 1))
    else
        print_warning "✗ Logger 'com.jfrog.jfconfig' (DEBUG) not found"
    fi
    
    if echo "$content" | grep -q "org.jfrog.jfconfig.*DEBUG"; then
        print_info "✓ Logger 'org.jfrog.jfconfig' (DEBUG) found"
        found_count=$((found_count + 1))
    else
        print_warning "✗ Logger 'org.jfrog.jfconfig' (DEBUG) not found"
    fi
    
    echo ""
    if [ "$ACTION" = "enable" ]; then
        if [ $found_count -eq 3 ]; then
            print_info "All loggers are enabled successfully!"
            echo ""
            print_info "To view the DEBUG logs in real-time, run:"
            echo "  kubectl logs -f $POD_NAME -c $CONTAINER_NAME -n $NAMESPACE"
            echo ""
            return 0
        else
            print_error "Not all loggers are enabled. Found $found_count out of 3."
            return 1
        fi
    else
        if [ $found_count -eq 0 ]; then
            print_info "All loggers are disabled successfully!"
            return 0
        else
            print_error "Not all loggers are disabled. Found $found_count still present."
            return 1
        fi
    fi
}

# Enable loggers
enable_loggers() {
    print_info "Enabling debug loggers..."
    
    # Check if loggers are already enabled
    if check_loggers; then
        print_warning "Loggers appear to be already enabled. Verifying..."
        verify_loggers
        return $?
    fi
    
    # Read current content
    local current_content
    current_content=$(kubectl exec "$POD_NAME" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- cat "$LOGBACK_INCLUDE_FILE" 2>/dev/null)
    
    # Create new content with loggers
    local new_content
    if echo "$current_content" | grep -q "<!--  Add custom loggers here -->"; then
        # Replace the comment with loggers
        new_content=$(echo "$current_content" | sed "s|<!--  Add custom loggers here -->|$LOGGER1\n$LOGGER2\n$LOGGER3|")
    else
        # Add loggers before </included>
        new_content=$(echo "$current_content" | sed "s|</included>|$LOGGER1\n$LOGGER2\n$LOGGER3\n</included>|")
    fi
    
    # Write new content back
    echo "$new_content" | kubectl exec -i "$POD_NAME" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- sh -c "cat > $LOGBACK_INCLUDE_FILE"
    
    if [ $? -eq 0 ]; then
        print_info "Loggers added successfully!"
        verify_loggers
        return $?
    else
        print_error "Failed to add loggers"
        return 1
    fi
}

# Disable loggers
disable_loggers() {
    print_info "Disabling debug loggers..."
    
    # Check if loggers are already disabled
    if ! check_loggers; then
        print_warning "Loggers appear to be already disabled. Verifying..."
        verify_loggers
        return $?
    fi
    
    # Remove all three loggers (using single line sed command with # delimiter to avoid / conflicts)
    kubectl exec "$POD_NAME" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- sed -i '#<logger name="org.springframework" level="DEBUG"/>#d; #<logger name="com.jfrog.jfconfig" level="DEBUG"/>#d; #<logger name="org.jfrog.jfconfig" level="DEBUG"/>#d' "$LOGBACK_INCLUDE_FILE"
    
    if [ $? -eq 0 ]; then
        print_info "Loggers removed successfully!"
        
        # Restore comment if file is empty (only has <included></included>)
        local content
        content=$(kubectl exec "$POD_NAME" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- cat "$LOGBACK_INCLUDE_FILE" 2>/dev/null)
        if ! echo "$content" | grep -q "<!--  Add custom loggers here -->"; then
            # Check if we need to add the comment back
            if echo "$content" | grep -q "^<included>$" && echo "$content" | grep -q "^</included>$"; then
                # File only has <included></included>, restore the comment
                local restored_content
                restored_content="<included>\n<!--  Add custom loggers here -->\n</included>"
                echo -e "$restored_content" | kubectl exec -i "$POD_NAME" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- sh -c "cat > $LOGBACK_INCLUDE_FILE"
            fi
        fi
        
        verify_loggers
        return $?
    else
        print_error "Failed to remove loggers"
        return 1
    fi
}

# Main execution
case "$ACTION" in
    enable)
        enable_loggers
        exit $?
        ;;
    disable)
        disable_loggers
        exit $?
        ;;
    *)
        print_error "Invalid action: $ACTION"
        exit 1
        ;;
esac

