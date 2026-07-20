import XCTest
@testable import YeelightBar

final class YeelightCommandTests: XCTestCase {
    func testEncodesSetPowerCommand() throws {
        let command = YeelightCommand.setPower(id: 7, isOn: true, duration: 500)
        let data = try command.framedData()
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, #"{"id":7,"method":"set_power","params":["on","smooth",500]}"# + "\r\n")
    }

    func testEncodesSceneColorFlowCommand() throws {
        let flow = ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .color(0x0000FF, brightness: 10, duration: 500),
                .sleep(1000)
            ]
        )
        let command = YeelightCommand.setSceneColorFlow(id: 8, flow: flow)
        let data = try command.framedData()
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, #"{"id":8,"method":"set_scene","params":["cf",0,0,"500,1,255,10,1000,7,0,0"]}"# + "\r\n")
    }

    func testEncodesStopFlowCommand() throws {
        let command = YeelightCommand.stopColorFlow(id: 9)
        let data = try command.framedData()
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, #"{"id":9,"method":"stop_cf","params":[]}"# + "\r\n")
    }

    func testDecodesResultAndNotification() throws {
        let result = try YeelightMessageDecoder.decode(lineData: Data(#"{"id":3,"result":["on","100"]}"#.utf8))
        XCTAssertEqual(result, .result(id: 3, values: [.string("on"), .string("100")]))

        let notification = try YeelightMessageDecoder.decode(lineData: Data(#"{"method":"props","params":{"power":"off","bright":"10"}}"#.utf8))
        XCTAssertEqual(notification, .notification(properties: ["power": "off", "bright": "10"]))
    }

    func testDecodesError() throws {
        let message = try YeelightMessageDecoder.decode(lineData: Data(#"{"id":4,"error":{"code":-1,"message":"unsupported method"}}"#.utf8))
        XCTAssertEqual(message, .failure(id: 4, error: YeelightErrorMessage(code: -1, message: "unsupported method")))
    }

    func testDecodesJSONBooleanBeforeNSNumberIntegerBridge() throws {
        let message = try YeelightMessageDecoder.decode(lineData: Data(#"{"id":5,"result":[true,false,1]}"#.utf8))
        XCTAssertEqual(message, .result(id: 5, values: [.bool(true), .bool(false), .int(1)]))
    }
}
