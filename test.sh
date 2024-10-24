cd tests/

test_count=0
for test_file in *-test.nix; do
    echo "Collecting results for... ${test_file}"
    result=$(nix eval --show-trace --impure --expr "import ./${test_file} {}")
    
    if [ "$result" != "[ ]" ]; then
        echo "Test failed: Expected [], but got $result in $test_file"
        exit 1
    fi
    ((test_count++))
done

echo "All tests in ${test_count} suites passed."
