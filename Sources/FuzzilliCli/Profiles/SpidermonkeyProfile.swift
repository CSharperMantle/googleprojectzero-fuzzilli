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

import Fuzzilli

fileprivate let ForceSpidermonkeyIonGenerator = CodeGenerator("ForceSpidermonkeyIonGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    b.callFunction(b.createNamedVariable(forBuiltin: "gc"))
}

fileprivate let MinorGcGenerator = CodeGenerator("MinorGcGenerator") { b in
    let minorgc = b.createNamedVariable(forBuiltin: "minorgc")
    if probability(0.5) {
        b.callFunction(minorgc, withArgs: [b.loadBool(probability(0.5))])
    } else {
        b.callFunction(minorgc)
    }
}

fileprivate let MaybeGcGenerator = CodeGenerator("MaybeGcGenerator") { b in
    b.callFunction(b.createNamedVariable(forBuiltin: "maybegc"))
}

fileprivate let IncrementalGcGenerator = CodeGenerator("IncrementalGcGenerator") { b in
    b.buildTryCatchFinally(
        tryBody: {
            let schedulezone = b.createNamedVariable(forBuiltin: "schedulezone")
            let startgc = b.createNamedVariable(forBuiltin: "startgc")
            let gcslice = b.createNamedVariable(forBuiltin: "gcslice")
            let finishgc = b.createNamedVariable(forBuiltin: "finishgc")
            let abortgc = b.createNamedVariable(forBuiltin: "abortgc")

            if b.hasVisibleVariables && probability(0.5) {
                b.callFunction(schedulezone, withArgs: [b.randomJsVariable()])
            } else {
                b.callFunction(schedulezone, withArgs: [b.loadString(b.randomString())])
            }

            let budget = b.loadInt(Int64.random(in: 1...2000))
            if probability(0.3) {
                b.callFunction(startgc, withArgs: [budget, b.loadString("shrinking")])
            } else {
                b.callFunction(startgc, withArgs: [budget])
            }

            for _ in 0..<Int.random(in: 1...3) {
                b.callFunction(gcslice, withArgs: [b.loadInt(Int64.random(in: 1...2000))])
            }

            if probability(0.8) {
                b.callFunction(finishgc)
            } else {
                b.callFunction(abortgc)
            }
        },
        catchBody: { _ in
        }
    )
}

fileprivate let GcZealGenerator = CodeGenerator("GcZealGenerator") { b in
    b.buildTryCatchFinally(
        tryBody: {
            let gczeal = b.createNamedVariable(forBuiltin: "gczeal")
            let unsetgczeal = b.createNamedVariable(forBuiltin: "unsetgczeal")
            let mode = b.loadInt(Int64.random(in: 0...24))

            if probability(0.75) {
                b.callFunction(gczeal, withArgs: [mode, b.loadInt(Int64.random(in: 1...50))])
            } else {
                b.callFunction(unsetgczeal, withArgs: [mode])
            }
        },
        catchBody: { _ in
        }
    )
}

fileprivate let SpidermonkeyStringShapeGenerator = CodeGenerator("SpidermonkeyStringShapeGenerator") { b in
    b.buildTryCatchFinally(
        tryBody: {
            let newString = b.createNamedVariable(forBuiltin: "newString")
            let newDependentString = b.createNamedVariable(forBuiltin: "newDependentString")
            let ensureLinearString = b.createNamedVariable(forBuiltin: "ensureLinearString")

            let base = b.callFunction(newString, withArgs: [b.loadString(b.randomString())])
            let startIndex = b.loadInt(Int64.random(in: 0...5))

            let candidate: Variable
            if probability(0.5) {
                let endIndex = b.loadInt(Int64.random(in: 6...20))
                candidate = b.callFunction(
                    newDependentString, withArgs: [base, startIndex, endIndex])
            } else {
                candidate = b.callFunction(newDependentString, withArgs: [base, startIndex])
            }

            _ = b.callFunction(ensureLinearString, withArgs: [candidate])
        },
        catchBody: { _ in
        }
    )
}

fileprivate let RelazifyFunctionsGenerator = CodeGenerator("RelazifyFunctionsGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)
    b.callFunction(b.createNamedVariable(forBuiltin: "relazifyFunctions"))
    b.callFunction(f, withArgs: arguments)
}

fileprivate let TrialInlineGenerator = CodeGenerator("TrialInlineGenerator") { b in
    let trialInline = b.createNamedVariable(forBuiltin: "trialInline")
    let f = b.buildPlainFunction(with: b.randomParameters()) { _ in
        b.build(n: Int.random(in: 3...8))
        if probability(0.7) {
            b.callFunction(trialInline)
        }
        b.doReturn(b.randomJsVariable())
    }

    let arguments = b.randomArguments(forCalling: f)
    b.buildRepeatLoop(n: Int.random(in: 5...20)) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let JobQueueGenerator = CodeGenerator("JobQueueGenerator") { b in
    b.callFunction(b.createNamedVariable(forBuiltin: "drainJobQueue"))
}

// From V8RegExpFuzzer
fileprivate let SpidermonkeyRegExpFuzzer = ProgramTemplate("SpidermonkeyRegExpFuzzer") { b in
    b.buildPrefix()
    b.build(n: 20)

    let twoByteSubjectString = "f\\uD83D\\uDCA9ba\\u2603"

    let replacementCandidates = [
        "X",
        "$1$2$3",
        "$$$&$`$'$1",
        "",
    ]

    let lastIndices = [
        "undefined", "-1", "0",
        "1", "2", "3",
        "4", "5", "6",
        "7", "8", "9",
        "50", "4294967296", "2147483647",
        "2147483648", "NaN", "Not a Number",
    ]

    let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
        let (pattern, flags) = b.randomRegExpPatternAndFlags()
        let regex = b.loadRegExp(pattern, flags)
        let symbol = b.createNamedVariable(forBuiltin: "Symbol")

        let lastIndexString = b.loadString(chooseUniform(from: lastIndices))
        b.setProperty("lastIndex", of: regex, to: lastIndexString)

        let subject =
            probability(0.15) ? b.loadString(twoByteSubjectString) : b.loadString(b.randomString())
        let result = b.loadNull()

        b.buildTryCatchFinally(
            tryBody: {
                withEqualProbability(
                    {
                        let res = b.callMethod("exec", on: regex, withArgs: [subject])
                        b.reassign(result, to: res)
                    },
                    {
                        let res = b.callMethod("test", on: regex, withArgs: [subject])
                        b.reassign(result, to: res)
                    },
                    {
                        let match = b.getProperty("match", of: symbol)
                        let res = b.callComputedMethod(match, on: regex, withArgs: [subject])
                        b.reassign(result, to: res)
                    },
                    {
                        let replace = b.getProperty("replace", of: symbol)
                        let replacement = withEqualProbability(
                            { b.loadString(b.randomString()) },
                            { b.loadString(chooseUniform(from: replacementCandidates)) },
                            {
                                b.buildPlainFunction(with: .parameters(n: 5)) { args in
                                    b.doReturn(
                                        withEqualProbability(
                                            { b.loadString(b.randomString()) },
                                            { b.randomJsVariable() }
                                        ))
                                }
                            }
                        )
                        let res = b.callComputedMethod(
                            replace, on: regex, withArgs: [subject, replacement])
                        b.reassign(result, to: res)
                    },
                    {
                        let search = b.getProperty("search", of: symbol)
                        let res = b.callComputedMethod(search, on: regex, withArgs: [subject])
                        b.reassign(result, to: res)
                    },
                    {
                        let split = b.getProperty("split", of: symbol)
                        let splitLimit = withEqualProbability(
                            { b.loadUndefined() },
                            { b.loadString("not a number") },
                            { b.loadInt(Int64.random(in: 0...128)) }
                        )
                        let res = b.callComputedMethod(
                            split, on: regex, withArgs: [subject, splitLimit])
                        b.reassign(result, to: res)
                    })

                if probability(0.5) {
                    b.callMethod("match", on: subject, withArgs: [regex])
                }

                b.build(n: 6)
            },
            catchBody: { _ in
            })

        b.build(n: 8)
        b.doReturn(result)
    }

    for _ in 0..<Int.random(in: 5...14) {
        b.callFunction(f)
    }

    b.build(n: 15)
}

fileprivate let SpidermonkeyIncrementalGcFuzzer = ProgramTemplate("SpidermonkeyIncrementalGcFuzzer") { b in
    b.buildPrefix()

    let schedulezone = b.createNamedVariable(forBuiltin: "schedulezone")
    let startgc = b.createNamedVariable(forBuiltin: "startgc")
    let gcslice = b.createNamedVariable(forBuiltin: "gcslice")
    let finishgc = b.createNamedVariable(forBuiltin: "finishgc")

    let targets = Int.random(in: 1...3)
    for _ in 0..<targets {
        let obj = b.createObject(with: ["v": b.randomJsVariable()])
        b.callFunction(schedulezone, withArgs: [obj])
    }

    b.callFunction(startgc, withArgs: [b.loadInt(Int64.random(in: 1...3000))])
    for _ in 0..<Int.random(in: 1...5) {
        b.build(n: Int.random(in: 3...12))
        b.callFunction(gcslice, withArgs: [b.loadInt(Int64.random(in: 1...2000))])
    }
    b.callFunction(finishgc)

    b.build(n: 10)
}

let spidermonkeyProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--asmjs",
            "--baseline-warmup-threshold=10",
            "--ion-warmup-threshold=100",
            "--ion-check-range-analysis",
            "--ion-extra-checks",
            "--fuzzing-safe",
            "--disable-oom-functions",
            "--reprl",
        ]

        guard randomize else { return args }

        args.append("--small-function-length=\(1<<Int.random(in: 7...12))")
        args.append("--inlining-entry-threshold=\(1<<Int.random(in: 2...10))")
        args.append("--gc-zeal=\(probability(0.5) ? UInt32(0) : UInt32(Int.random(in: 1...24)))")
        args.append("--ion-scalar-replacement=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-pruning=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-range-analysis=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-inlining=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-gvn=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-osr=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-edgecase-analysis=\(probability(0.9) ? "on" : "off")")
        args.append("--nursery-size=\(1<<Int.random(in: 0...5))")
        args.append("--nursery-strings=\(probability(0.9) ? "on" : "off")")
        args.append("--nursery-bigints=\(probability(0.9) ? "on" : "off")")
        args.append("--spectre-mitigations=\(probability(0.1) ? "on" : "off")")
        if probability(0.1) {
            args.append("--no-native-regexp")
        }
        args.append("--ion-optimize-shapeguards=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-optimize-gcbarriers=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-licm=\(probability(0.9) ? "on" : "off")")
        args.append("--ion-instruction-reordering=\(probability(0.9) ? "on" : "off")")
        args.append("--cache-ir-stubs=\(probability(0.9) ? "on" : "off")")
        args.append(
            chooseUniform(from: [
                "--no-sse3", "--no-ssse3", "--no-sse41", "--no-sse42", "--enable-avx",
            ]))
        if probability(0.1) {
            args.append("--ion-regalloc=testbed")
        }
        args.append("--\(probability(0.9) ? "enable" : "disable")-watchtower")
        args.append("--ion-sink=\(probability(0.0) ? "on" : "off")")  // disabled
        args.append("--\(probability(0.9) ? "no-" : "")emit-interpreter-entry")
        if probability(0.1) {
            args.append("--enable-ic-frame-pointers")
        }
        if probability(0.1) {
            args.append("--scalar-replace-arguments")
        }
        args.append("--monomorphic-inlining=\(probability(0.9) ? "default" : "always")")
        if probability(0.1) {
            args.append("--more-compartments")
        }
        args.append("--\(probability(0.9) ? "enable" : "no")-parallel-marking")
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
        (ForceSpidermonkeyIonGenerator,    10),
        (RelazifyFunctionsGenerator,        5),
        (TrialInlineGenerator,              5),
        (GcGenerator,                      10),
        (MinorGcGenerator,                  5),
        (MaybeGcGenerator,                  5),
        (IncrementalGcGenerator,            5),
        (GcZealGenerator,                   5),
        (SpidermonkeyStringShapeGenerator, 10),
        (JobQueueGenerator,                 5),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (SpidermonkeyRegExpFuzzer,          1),
        (SpidermonkeyIncrementalGcFuzzer,   1),
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc": .function([] => .undefined),
        "minorgc": .function([.opt(.boolean)] => .undefined),
        "maybegc": .function([] => .undefined),
        "gczeal": .function([.opt(.integer), .opt(.integer)] => .undefined),
        "unsetgczeal": .function([.integer] => .undefined),
        "schedulezone": .function([.jsAnything] => .undefined),
        "startgc": .function([.opt(.integer), .opt(.string)] => .undefined),
        "gcslice": .function([.opt(.integer), .opt(.object())] => .undefined),
        "finishgc": .function([] => .undefined),
        "abortgc": .function([] => .undefined),
        "gcstate": .function([.opt(.jsAnything)] => .jsAnything),
        "relazifyFunctions": .function([] => .undefined),
        "trialInline": .function([] => .undefined),
        "newString": .function([.string, .opt(.object())] => .string),
        "newDependentString": .function([.string, .integer, .opt(.integer), .opt(.object())] => .string),
        "ensureLinearString": .function([.string] => .string),
        "addWatchtowerTarget": .function([.object()] => .undefined),
        "getWatchtowerLog": .function([] => .object()),
        "getBuildConfiguration": .function([.opt(.string)] => .jsAnything),
        "getRealmConfiguration": .function([.opt(.string)] => .jsAnything),
        "drainJobQueue": .function([] => .undefined),
        "bailout": .function([] => .undefined),
        "bailAfter": .function([.number] => .undefined),
        "invalidate": .function([] => .undefined),
        "settlePromiseNow": .function([.object()] => .undefined),
        "getWaitForAllPromise": .function([.object()] => .jsPromise),
        "resolvePromise": .function([.object(), .jsAnything] => .undefined),
        "rejectPromise": .function([.object(), .jsAnything] => .undefined),
    ],

    additionalObjectGroups: [],

    additionalEnumerations: [],

    optionalPostProcessor: nil
)
