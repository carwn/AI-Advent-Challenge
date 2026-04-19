import XCTest
@testable import AI_Advent_Challenge

// Unit-тесты для DefaultCalculatorService — чистая математика, без сети.

final class CalculatorServiceTests: XCTestCase {

    private let calculator = DefaultCalculatorService()

    // MARK: - Add

    func test_add_twoNumbers_returnsSum() throws {
        let result = try calculator.calculate(operation: "add", operands: [3, 5])
        XCTAssertEqual(result, 8)
    }

    func test_add_multipleNumbers_returnsSum() throws {
        let result = try calculator.calculate(operation: "add", operands: [1, 2, 3, 4])
        XCTAssertEqual(result, 10)
    }

    func test_add_negativeNumbers_returnsCorrectSum() throws {
        let result = try calculator.calculate(operation: "add", operands: [-5, 3])
        XCTAssertEqual(result, -2)
    }

    func test_add_singleNumber_returnsSameNumber() throws {
        let result = try calculator.calculate(operation: "add", operands: [42])
        XCTAssertEqual(result, 42)
    }

    // MARK: - Subtract

    func test_subtract_twoNumbers_returnsDifference() throws {
        let result = try calculator.calculate(operation: "subtract", operands: [10, 3])
        XCTAssertEqual(result, 7)
    }

    func test_subtract_multipleNumbers_chainsSubtraction() throws {
        // 20 - 5 - 3 = 12
        let result = try calculator.calculate(operation: "subtract", operands: [20, 5, 3])
        XCTAssertEqual(result, 12)
    }

    func test_subtract_oneOperand_throwsInvalidArguments() {
        XCTAssertThrowsError(try calculator.calculate(operation: "subtract", operands: [5])) { error in
            guard case ToolExecutionError.invalidArguments = error else {
                XCTFail("Expected invalidArguments, got \(error)")
                return
            }
        }
    }

    // MARK: - Multiply

    func test_multiply_twoNumbers_returnsProduct() throws {
        let result = try calculator.calculate(operation: "multiply", operands: [4, 5])
        XCTAssertEqual(result, 20)
    }

    func test_multiply_byZero_returnsZero() throws {
        let result = try calculator.calculate(operation: "multiply", operands: [100, 0])
        XCTAssertEqual(result, 0)
    }

    func test_multiply_multipleNumbers_returnsProduct() throws {
        // 2 * 3 * 4 = 24
        let result = try calculator.calculate(operation: "multiply", operands: [2, 3, 4])
        XCTAssertEqual(result, 24)
    }

    func test_multiply_negativeNumbers_returnsPositive() throws {
        let result = try calculator.calculate(operation: "multiply", operands: [-3, -4])
        XCTAssertEqual(result, 12)
    }

    // MARK: - Divide

    func test_divide_twoNumbers_returnsQuotient() throws {
        let result = try calculator.calculate(operation: "divide", operands: [10, 2])
        XCTAssertEqual(result, 5)
    }

    func test_divide_returnsDecimal() throws {
        let result = try calculator.calculate(operation: "divide", operands: [7, 2])
        XCTAssertEqual(result, 3.5)
    }

    func test_divide_byZero_throwsExecutionFailed() {
        XCTAssertThrowsError(try calculator.calculate(operation: "divide", operands: [10, 0])) { error in
            guard case ToolExecutionError.executionFailed = error else {
                XCTFail("Expected executionFailed (division by zero), got \(error)")
                return
            }
        }
    }

    func test_divide_oneOperand_throwsInvalidArguments() {
        XCTAssertThrowsError(try calculator.calculate(operation: "divide", operands: [5])) { error in
            guard case ToolExecutionError.invalidArguments = error else {
                XCTFail("Expected invalidArguments, got \(error)")
                return
            }
        }
    }

    func test_divide_multipleOperands_chainesDivision() throws {
        // 100 / 5 / 4 = 5
        let result = try calculator.calculate(operation: "divide", operands: [100, 5, 4])
        XCTAssertEqual(result, 5)
    }

    // MARK: - Edge cases

    func test_emptyOperands_throwsInvalidArguments() {
        XCTAssertThrowsError(try calculator.calculate(operation: "add", operands: [])) { error in
            guard case ToolExecutionError.invalidArguments = error else {
                XCTFail("Expected invalidArguments, got \(error)")
                return
            }
        }
    }

    func test_unknownOperation_throwsUnsupportedTool() {
        XCTAssertThrowsError(try calculator.calculate(operation: "modulo", operands: [10, 3])) { error in
            guard case ToolExecutionError.unsupportedTool = error else {
                XCTFail("Expected unsupportedTool, got \(error)")
                return
            }
        }
    }

    func test_add_floatingPoint_returnsPreciseResult() throws {
        let result = try calculator.calculate(operation: "add", operands: [0.1, 0.2])
        XCTAssertEqual(result, 0.3, accuracy: 1e-10)
    }
}
