import XCTest
@testable import YeelightBar

final class LightPresetTests: XCTestCase {
    func testLightControlModeInferenceMatchesDeviceState() {
        XCTAssertEqual(LightControlMode.inferred(from: DeviceState(colorMode: .colorTemperature)), .white)
        XCTAssertEqual(LightControlMode.inferred(from: DeviceState(colorMode: .rgb)), .color)
        XCTAssertEqual(LightControlMode.inferred(from: DeviceState(colorMode: .hsv)), .color)
        XCTAssertEqual(LightControlMode.inferred(from: DeviceState(colorMode: .rgb, flowing: true)), .flow)
    }

    func testDeviceStateColorModeTransitions() {
        var state = DeviceState(colorMode: .rgb, flowing: true, flowParameters: "500,1,255,100")
        state.apply(properties: ["ct": "4200", "flowing": "0", "flow_params": ""])

        XCTAssertEqual(state.colorMode, .colorTemperature)
        XCTAssertEqual(LightControlMode.inferred(from: state), .white)
        XCTAssertFalse(state.flowing)
        XCTAssertEqual(state.flowParameters, "")

        state.apply(properties: ["rgb": "16711680"])

        XCTAssertEqual(state.colorMode, .rgb)
        XCTAssertEqual(LightControlMode.inferred(from: state), .color)
    }

    func testFlowExpressionEncodesTuples() {
        let flow = ColorFlow(
            count: 4,
            stopAction: .turnOff,
            steps: [
                .colorTemperature(2700, brightness: 100, duration: 1000),
                .color(0x0000FF, brightness: 10, duration: 500),
                .sleep(5000)
            ]
        )

        XCTAssertEqual(flow.expression, "1000,2,2700,100,500,1,255,10,5000,7,0,0")
    }

    func testFlowStepClampsValues() {
        let step = FlowStep(mode: .color, duration: 1, rgb: 0x1FFFFFF, brightness: 200)

        XCTAssertEqual(step.duration, 50)
        XCTAssertEqual(step.rgb, 0xFFFFFF)
        XCTAssertEqual(step.brightness, 100)
        XCTAssertEqual(step.encodedTuple, [50, 1, 0xFFFFFF, 100])
    }

    func testFlowCycleCountMapsToProtocolTransitions() {
        XCTAssertEqual(ColorFlow.count(forCycles: 3, stepCount: 4), 12)
        XCTAssertEqual(ColorFlow.count(forCycles: 1, stepCount: 1), 1)
        XCTAssertEqual(ColorFlow.count(forCycles: 100, stepCount: 100), 10_000)
        XCTAssertNil(ColorFlow.count(forCycles: 0, stepCount: 4))
        XCTAssertNil(ColorFlow.count(forCycles: 1, stepCount: 0))
        XCTAssertNil(ColorFlow.count(forCycles: 101, stepCount: 100))
        XCTAssertNil(ColorFlow.count(forCycles: Int.max, stepCount: 2))
    }

    func testFlowSummaryDistinguishesCyclesInfiniteAndLegacyTransitions() {
        let steps: [FlowStep] = [
            .color(0xFF0000, duration: 500),
            .sleep(500)
        ]
        let infinite = LightPreset(
            id: "infinite",
            title: "Infinite",
            kind: .flow,
            flow: ColorFlow(count: 0, stopAction: .recover, steps: steps)
        )
        let finite = LightPreset(
            id: "finite",
            title: "Finite",
            kind: .flow,
            flow: ColorFlow(count: 6, stopAction: .stay, steps: steps)
        )
        let legacyPartial = LightPreset(
            id: "legacy",
            title: "Legacy",
            kind: .flow,
            flow: ColorFlow(count: 3, stopAction: .turnOff, steps: steps)
        )

        XCTAssertEqual(infinite.summary, "2 steps · repeats forever · Recover")
        XCTAssertEqual(finite.summary, "2 steps · 3 cycles · Stay")
        XCTAssertEqual(legacyPartial.summary, "2 steps · 3 transitions · Turn Off")
    }

    func testBuiltInPresetIDsAreUnique() {
        let ids = LightPreset.builtIns.map(\.id)

        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testBuiltInFlowPresetsIncludeExpandedFunctionalSet() {
        let flowPresets = LightPreset.builtIns.filter { $0.kind == .flow }
        let flowPresetIDs = Set(flowPresets.map(\.id))

        XCTAssertTrue(flowPresetIDs.contains(LightPreset.calmBreathing.id))
        XCTAssertTrue(flowPresetIDs.contains(LightPreset.deepFocusPulse.id))
        XCTAssertTrue(flowPresetIDs.contains(LightPreset.dinnerWarmth.id))
        XCTAssertTrue(flowPresetIDs.contains(LightPreset.tvAmbient.id))
        XCTAssertTrue(flowPresetIDs.contains(LightPreset.partyPulse.id))
        XCTAssertTrue(flowPresetIDs.contains(LightPreset.findBulb.id))

        let newFlowIDs = [
            LightPreset.calmBreathing.id,
            LightPreset.deepFocusPulse.id,
            LightPreset.dinnerWarmth.id,
            LightPreset.tvAmbient.id,
            LightPreset.partyPulse.id,
            LightPreset.findBulb.id
        ]
        XCTAssertTrue(newFlowIDs.allSatisfy { !LightPreset.defaultFavoriteIDs.contains($0) })

        for preset in flowPresets {
            XCTAssertTrue(preset.isBuiltIn)
            XCTAssertEqual(preset.kind, .flow)
            XCTAssertNotNil(preset.flow)
            XCTAssertTrue(preset.flow?.isValid == true)
            XCTAssertFalse(preset.flow?.expression.isEmpty ?? true)

            if let flow = preset.flow, flow.count > 0 {
                XCTAssertEqual(flow.count, flow.steps.count)
            }
        }
    }

    func testDeviceStateDecodesLegacySavedState() throws {
        let legacyJSON = """
        {
          "power": "on",
          "brightness": 55,
          "colorTemperature": 3000,
          "rgb": 65280,
          "hue": 120,
          "saturation": 70,
          "colorMode": 1,
          "online": true
        }
        """

        let state = try JSONDecoder().decode(DeviceState.self, from: Data(legacyJSON.utf8))

        XCTAssertTrue(state.online)
        XCTAssertFalse(state.flowing)
        XCTAssertEqual(state.flowParameters, "")
        XCTAssertEqual(state.delayOffMinutes, 0)
    }

    func testDeviceStateParsesFlowProperties() {
        var state = DeviceState.unknown
        state.apply(properties: [
            "flowing": "1",
            "flow_params": "500,1,255,100",
            "delayoff": "15"
        ])

        XCTAssertTrue(state.flowing)
        XCTAssertEqual(state.flowParameters, "500,1,255,100")
        XCTAssertEqual(state.delayOffMinutes, 15)
    }
}
