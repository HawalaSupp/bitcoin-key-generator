#!/bin/bash
# Convert XCTest files to Swift Testing framework

cd /Users/x/Desktop/888/swift-app/Tests/swift-appTests

for file in *.swift; do
  if grep -q "import XCTest" "$file"; then
    echo "Converting: $file"
    
    # Replace import
    sed -i '' 's/import XCTest/import Testing/' "$file"
    
    # Replace class declarations
    sed -i '' 's/final class \([A-Za-z0-9_]*\): XCTestCase/@Suite\nstruct \1/' "$file"
    sed -i '' 's/class \([A-Za-z0-9_]*\): XCTestCase/@Suite\nstruct \1/' "$file"
    
    # Replace XCTAssertTrue
    sed -i '' 's/XCTAssertTrue(\([^)]*\))/#expect(\1)/g' "$file"
    
    # Replace XCTAssertFalse  
    sed -i '' 's/XCTAssertFalse(\([^)]*\))/#expect(!(\1))/g' "$file"
    
    # Replace XCTAssertEqual
    sed -i '' 's/XCTAssertEqual(\([^,]*\), \([^)]*\))/#expect(\1 == \2)/g' "$file"
    
    # Replace XCTAssertNil
    sed -i '' 's/XCTAssertNil(\([^)]*\))/#expect(\1 == nil)/g' "$file"
    
    # Replace XCTAssertNotNil  
    sed -i '' 's/XCTAssertNotNil(\([^)]*\))/#expect(\1 != nil)/g' "$file"
    
    # Replace XCTFail
    sed -i '' 's/XCTFail(\([^)]*\))/#expect(Bool(false), \1)/g' "$file"
    
    # Add @Test annotation to test functions
    sed -i '' 's/func test\([A-Za-z0-9_]*\)() throws/@Test func test\1() throws/g' "$file"
    sed -i '' 's/func test\([A-Za-z0-9_]*\)() async/@Test func test\1() async/g' "$file"
    sed -i '' 's/func test\([A-Za-z0-9_]*\)()$/@Test func test\1()/g' "$file"
    
    echo "  Done"
  fi
done

echo "Conversion complete!"
