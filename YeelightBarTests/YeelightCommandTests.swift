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

    func testEncodesPowerOffTimerCommandsAtProtocolBoundaries() throws {
        let minimum = try XCTUnwrap(SleepTimerMinutes(1))
        let maximum = try XCTUnwrap(SleepTimerMinutes(60))

        let addMinimum = String(
            data: try YeelightCommand.addPowerOffTimer(id: 10, minutes: minimum).framedData(),
            encoding: .utf8
        )
        let addMaximum = String(
            data: try YeelightCommand.addPowerOffTimer(id: 11, minutes: maximum).framedData(),
            encoding: .utf8
        )
        let get = String(data: try YeelightCommand.getPowerOffTimer(id: 12).framedData(), encoding: .utf8)
        let delete = String(data: try YeelightCommand.deletePowerOffTimer(id: 13).framedData(), encoding: .utf8)

        XCTAssertEqual(addMinimum, #"{"id":10,"method":"cron_add","params":[0,1]}"# + "\r\n")
        XCTAssertEqual(addMaximum, #"{"id":11,"method":"cron_add","params":[0,60]}"# + "\r\n")
        XCTAssertEqual(get, #"{"id":12,"method":"cron_get","params":[0]}"# + "\r\n")
        XCTAssertEqual(delete, #"{"id":13,"method":"cron_del","params":[0]}"# + "\r\n")
    }

    func testEncodesAutoDelayOffScene() throws {
        let minutes = try XCTUnwrap(SleepTimerMinutes(30))
        let command = YeelightCommand.setSceneAutoDelayOff(id: 14, brightness: 5, minutes: minutes)
        let string = String(data: try command.framedData(), encoding: .utf8)

        XCTAssertEqual(
            string,
            #"{"id":14,"method":"set_scene","params":["auto_delay_off",5,30]}"# + "\r\n"
        )
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
