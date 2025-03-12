#!/usr/bin/env bash

run_tests() {
    local dir=$1
    local test_count=0
    
    echo "Running tests in ${dir}..."
    cd "$dir" || { echo "Error: Directory $dir not found"; exit 1; }
    
    for test_file in *-test.nix; do
        [[ -e "$test_file" ]] || { echo "No test files found in $dir"; break; }
        
        echo "Collecting results for... ${test_file}"
        result=$(nix eval --show-trace --impure --expr "import ./${test_file} {}")
        
        if [ "$result" != "[ ]" ]; then
            echo "Test failed: Expected [], but got $result in $test_file"
            exit 1
        fi
        
        ((test_count++))
    done
    
    echo "All tests in ${test_count} suites passed in $dir."
    cd ..
}

run_tests "tests"

run_tests "tests/state"

echo "All tests completed successfully!"
