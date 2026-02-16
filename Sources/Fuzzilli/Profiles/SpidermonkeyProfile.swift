// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

private let ForceSpidermonkeyIonGenerator = CodeGenerator(
    "ForceSpidermonkeyIonGenerator", inputs: .required(.function())
) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

private let GcGenerator = CodeGenerator("GcGenerator") { b in
    b.callFunction(b.createNamedVariable(forBuiltin: "gc"))
}

let spidermonkeyProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--ion-check-range-analysis",
            "--ion-extra-checks",
            "--fuzzing-safe",
            "--disable-oom-functions",
            "--reprl",
        ]

        guard randomize else {
            args.append("--baseline-warmup-threshold=10")
            args.append("--ion-warmup-threshold=100")
            return args
        }

        args.append("--baseline-warmup-threshold=\(1<<Int.random(in: 0...6))")
        args.append("--ion-warmup-threshold=\(1<<Int.random(in: 3...10))")
        args.append("--small-function-length=\(1<<Int.random(in: 7...12))")
        args.append("--inlining-entry-threshold=\(1<<Int.random(in: 2...10))")
        args.append("--gc-zeal=\(probability(0.5) ? UInt32(0) : UInt32(Int.random(in: 1...24)))")
        args.append("--ion-scalar-replacement=\(probability(0.9) ? "on": "off")")
        args.append("--ion-pruning=\(probability(0.9) ? "on": "off")")
        args.append("--ion-range-analysis=\(probability(0.9) ? "on": "off")")
        args.append("--ion-inlining=\(probability(0.9) ? "on": "off")")
        args.append("--ion-gvn=\(probability(0.9) ? "on": "off")")
        args.append("--ion-osr=\(probability(0.9) ? "on": "off")")
        args.append("--ion-edgecase-analysis=\(probability(0.9) ? "on": "off")")
        args.append("--nursery-size=\(1<<Int.random(in: 0...5))")
        args.append("--nursery-strings=\(probability(0.9) ? "on": "off")")
        args.append("--nursery-bigints=\(probability(0.9)  ? "on": "off")")
        args.append("--spectre-mitigations=\(probability(0.1) ? "on": "off")")
        if probability(0.1) {
            args.append("--no-native-regexp")
        }
        args.append("--ion-optimize-shapeguards=\(probability(0.9) ? "on": "off")")
        args.append("--ion-optimize-gcbarriers=\(probability(0.9) ? "on": "off")")
        args.append("--ion-licm=\(probability(0.9) ? "on": "off")")
        args.append("--ion-instruction-reordering=\(probability(0.9) ? "on": "off")")
        args.append("--cache-ir-stubs=\(probability(0.9) ? "on": "off")")
        args.append(
            chooseUniform(from: [
                "--no-sse3", "--no-ssse3", "--no-sse41", "--no-sse42", "--enable-avx",
            ]))
        args.append("--\(probability(0.9) ? "no-": "")emit-interpreter-entry")
        if probability(0.1) {
            args.append("--enable-ic-frame-pointers")
        }
        if probability(0.1) {
            args.append("--scalar-replace-arguments")
        }
        args.append("--monomorphic-inlining=\(probability(0.9) ? "default": "always")")
        if probability(0.1) {
            args.append("--more-compartments")
        }
        args.append("--\(probability(0.9) ? "enable": "no")-parallel-marking")
        args.append("--ion-iterator-indices=\(probability(0.7) ? "on": "off")")
        args.append("--write-protect-code=\(probability(0.8) ? "on": "off")")
        args.append("--object-keys-scalar-replacement=\(probability(0.5) ? "on": "off")")
        if probability(0.1) {
            args.append("--ion-regalloc=\(chooseUniform(from: ["backtracking", "simple"]))")
        }
        if probability(0.1) {
            args.append("--ion-eager")
        }
        if probability(0.2) {
            args.append("--fast-warmup")
        }
        if probability(0.05) {
            args.append("--blinterp-eager")
        } else if probability(0.1) {
            args.append("--no-blinterp")
        }
        if probability(0.1) {
            args.append("--ion-limit-script-size=off")
        }
        if probability(0.1) {
            args.append("--no-cgc")
        }
        if probability(0.1) {
            args.append("--no-ggc")
        }
        if probability(0.1) {
            args.append("--no-incremental-gc")
        }
        if probability(0.05) {
            args.append("--no-jit-backend")
        }
        return args
    },

    processArgsReference: nil,

    processEnv: ["UBSAN_OPTIONS": "handle_segv=0"],

    maxExecsBeforeRespawn: 1000,

    timeout: Timeout.value(250),

    codePrefix: """
        """,

    codeSuffix: """
        gc();
        """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // Check that the fuzzilli integration is available.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        // Check that common crash types are detected.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldCrash),

        // TODO we could try to check that OOM crashes are ignored here ( with.shouldNotCrash).
    ],

    additionalCodeGenerators: [
        (ForceSpidermonkeyIonGenerator, 10),
        (GcGenerator, 10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc": .function([] => .undefined),
        "drainJobQueue": .function([] => .undefined),
        "bailout": .function([] => .undefined),
    ],

    additionalObjectGroups: [],

    additionalEnumerations: [],

    additionalOptionsBags: [],

    optionalPostProcessor: nil
)
