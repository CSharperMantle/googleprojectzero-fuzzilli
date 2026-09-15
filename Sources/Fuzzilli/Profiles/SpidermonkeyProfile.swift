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

            // schedulezone([obj | string]) throws for other types.
            if b.hasVisibleVariables && probability(0.5),
                let obj = b.randomVariable(ofType: .object())
            {
                b.callFunction(schedulezone, withArgs: [obj])
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
            // Match ZealMode::Limit
            let mode = b.loadInt(Int64.random(in: 0...27))

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

            // Results must exceed MAX_LENGTH_LATIN1/MAX_LENGTH_TWO_BYTE (vm/StringType.h),
            // otherwise the result fits into an inline string and newDependentString() throws.
            let twoByte = probability(0.25)
            let minResultLength = (twoByte ? 12 : 24) + 1
            let baseLength = Int.random(in: 30...120)
            func randomBaseString(_ length: Int) -> String {
                twoByte
                    ? String.random(ofLength: length, withCharSet: Array("\u{202E}\u{2603}\u{FFFD}"))
                    : String.random(ofLength: length)
            }

            let base: Variable
            if probability(0.2) {
                let newRope = b.createNamedVariable(forBuiltin: "newRope")
                let halfLength = baseLength / 2
                base = b.callFunction(newRope, withArgs: [
                    b.loadString(randomBaseString(halfLength)),
                    b.loadString(randomBaseString(baseLength - halfLength)),
                ])
            } else {
                var newStringArgs = [b.loadString(randomBaseString(baseLength))]
                if probability(0.3) {
                    newStringArgs.append(b.createObject(with: [
                        (twoByte ? "twoByte" : "tenured"): b.loadBool(true),
                    ]))
                }
                base = b.callFunction(newString, withArgs: newStringArgs)
            }

            // A start of 0 with no end index would return the base string itself,
            // which is not a dependent string.
            var candidateArgs = [base]
            let resultLength = Int.random(in: minResultLength...(baseLength - 1))
            if probability(0.7) {
                let startIndex = Int.random(in: 0...(baseLength - resultLength))
                candidateArgs.append(b.loadInt(Int64(startIndex)))
                candidateArgs.append(b.loadInt(Int64(startIndex + resultLength)))
            } else {
                let startIndex = Int.random(in: 1...(baseLength - resultLength))
                candidateArgs.append(b.loadInt(Int64(startIndex)))
            }
            if probability(0.3) {
                candidateArgs.append(b.createObject(with: [
                    "tenured": b.loadBool(probability(0.5)),
                    "suppress-contraction": b.loadBool(probability(0.5)),
                ]))
            }

            let candidate = b.callFunction(newDependentString, withArgs: candidateArgs)
            if probability(0.8) {
                _ = b.callFunction(ensureLinearString, withArgs: [candidate])
            }
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

fileprivate let IonDisableGenerator = CodeGenerator("IonDisableGenerator") { b in
    let f = b.buildPlainFunction(with: b.randomParameters()) { _ in
        // The with ({}) {} pattern at function start disables Ion compilation
        let emptyObj = b.createObject(with: [:])
        b.buildWith(emptyObj) {
            // Empty body
        }
        // Generate substantial function body to exercise interpreter coverage
        b.build(n: 20)
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

private let JitCompilerOptionGenerator = CodeGenerator("JitCompilerOptionGenerator") { b in
    let setJitCompilerOption = b.createNamedVariable(forBuiltin: "setJitCompilerOption")

    // Option names and sane value ranges, JIT_COMPILER_OPTIONS (jsapi.h). Values persist
    // for the worker's lifetime, so they stay within randomized-flag territory.
    let options: [(String, ClosedRange<Int64>)] = [
        ("ion.warmup.trigger", 0...1024),
        ("baseline.warmup.trigger", 0...1024),
        ("ion.gvn.enable", 0...1),
        ("ic.force-megamorphic", 0...1),
        ("ion.forceinlineCaches", 0...1),
        ("inlining.bytecode-max-length", 10...1000),
        ("ion.frequent-bailout-threshold", 0...1000),
        ("offthread-compilation.enable", 0...1),
    ]

    let (name, range) = chooseUniform(from: options)
    b.callFunction(setJitCompilerOption, withArgs: [
        b.loadString(name), b.loadInt(Int64.random(in: range)),
    ])
    b.build(n: Int.random(in: 5...15))
}

private let WatchtowerGenerator = CodeGenerator("WatchtowerGenerator") { b in
    let addWatchtowerTarget = b.createNamedVariable(forBuiltin: "addWatchtowerTarget")
    let getWatchtowerLog = b.createNamedVariable(forBuiltin: "getWatchtowerLog")

    let obj = b.createObject(with: [b.randomPropertyName(): b.randomJsVariable()])
    b.callFunction(addWatchtowerTarget, withArgs: [obj])

    b.buildRepeatLoop(n: Int.random(in: 5...20)) { _ in
        withEqualProbability({
            b.setProperty(b.randomPropertyName(), of: obj, to: b.randomJsVariable())
        }, {
            b.deleteProperty(b.randomPropertyName(), of: obj)
        }, {
            let Object = b.createNamedVariable(forBuiltin: "Object")
            b.callMethod("defineProperty", on: Object, withArgs: [
                obj, b.loadString(b.randomPropertyName()), b.createObject(with: [:]),
            ])
        })
    }

    b.callFunction(getWatchtowerLog)
}

private let ObjectFuseGenerator = CodeGenerator("ObjectFuseGenerator") { b in
    let addObjectFuse = b.createNamedVariable(forBuiltin: "addObjectFuse")
    let getObjectFuseState = b.createNamedVariable(forBuiltin: "getObjectFuseState")

    b.buildTryCatchFinally(
        tryBody: {
            let obj = b.createObject(with: [b.randomPropertyName(): b.randomJsVariable()])
            b.callFunction(addObjectFuse, withArgs: [obj])

            b.buildRepeatLoop(n: Int.random(in: 5...15)) { _ in
                b.setProperty(b.randomPropertyName(), of: obj, to: b.randomJsVariable())
            }
            b.callFunction(getObjectFuseState, withArgs: [obj])
        },
        catchBody: { _ in
        }
    )
}

private let GCParamGenerator = CodeGenerator("GCParamGenerator") { b in
    let gcparam = b.createNamedVariable(forBuiltin: "gcparam")

    // Writable, fuzzing-safe parameters (FOR_EACH_GC_PARAM in gc/GC.h). maxBytes and
    // maxNurseryBytes are skipped under --disable-oom-functions, semispaceNurseryEnabled
    // under --fuzzing-safe, concurrentMarkingEnabled rejects 1 in this build, and
    // nurseryEnabled fails under --no-ggc — hence the try/catch. Values persist for the
    // worker's lifetime.
    let params: [(String, ClosedRange<Int64>)] = [
        ("minNurseryBytes", 1 << 16...1 << 20),
        ("sliceTimeBudgetMS", 1...1000),
        ("allocationThreshold", 1...4095),
        ("smallHeapSizeMax", 1...200),
        ("largeHeapSizeMin", 1...200),
        ("heapGrowthFactor", 100...1000),
        ("incrementalGCEnabled", 0...1),
        ("perZoneGCEnabled", 0...1),
        ("compactingEnabled", 0...1),
        ("nurseryEnabled", 0...1),
        ("parallelMarkingEnabled", 0...1),
        ("balancedHeapLimitsEnabled", 0...1),
    ]

    let (name, range) = chooseUniform(from: params)
    b.buildTryCatchFinally(
        tryBody: {
            b.callFunction(gcparam, withArgs: [b.loadString(name), b.loadInt(Int64.random(in: range))])
        },
        catchBody: { _ in
        }
    )
    b.build(n: Int.random(in: 5...15))
}

private let BailoutStormGenerator = CodeGenerator("BailoutStormGenerator") { b in
    let bailout = b.createNamedVariable(forBuiltin: "bailout")
    let bailAfter = b.createNamedVariable(forBuiltin: "bailAfter")

    let f = b.buildPlainFunction(with: b.randomParameters()) { _ in
        b.build(n: Int.random(in: 5...15))
        b.doReturn(b.randomJsVariable())
    }

    b.callFunction(bailAfter, withArgs: [b.loadInt(Int64.random(in: 1...50))])
    let arguments = b.randomArguments(forCalling: f)
    b.buildRepeatLoop(n: Int.random(in: 50...200)) { _ in
        b.callFunction(f, withArgs: arguments)
        if probability(0.2) {
            b.callFunction(bailout)
        }
    }
}

private let GeneratorResumeGenerator = CodeGenerator("GeneratorResumeGenerator") { b in
    let minorgc = b.createNamedVariable(forBuiltin: "minorgc")

    let f = b.buildGeneratorFunction(with: b.randomParameters()) { _ in
        b.build(n: Int.random(in: 2...5))
        for _ in 0..<Int.random(in: 2...4) {
            b.yield(b.randomJsVariable())
            b.build(n: Int.random(in: 1...4))
            if probability(0.3) {
                b.callFunction(minorgc)
            }
        }
        b.doReturn(b.randomJsVariable())
    }

    let arguments = b.randomArguments(forCalling: f)
    b.buildRepeatLoop(n: Int.random(in: 10...40)) { _ in
        let it = b.callFunction(f, withArgs: arguments)
        b.buildRepeatLoop(n: Int.random(in: 2...6)) { _ in
            b.callMethod("next", on: it)
        }
    }
}

private let AsyncResumeGenerator = CodeGenerator("AsyncResumeGenerator") { b in
    let drainJobQueue = b.createNamedVariable(forBuiltin: "drainJobQueue")

    let f = b.buildAsyncFunction(with: b.randomParameters()) { _ in
        b.build(n: Int.random(in: 2...5))
        for _ in 0..<Int.random(in: 1...3) {
            b.await(b.randomJsVariable())
            b.build(n: Int.random(in: 1...4))
        }
        b.doReturn(b.randomJsVariable())
    }

    let arguments = b.randomArguments(forCalling: f)
    b.buildRepeatLoop(n: Int.random(in: 5...20)) { _ in
        b.callFunction(f, withArgs: arguments)
        b.callFunction(drainJobQueue)
    }
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
                        b.reassign(variable: result, value: res)
                    },
                    {
                        let res = b.callMethod("test", on: regex, withArgs: [subject])
                        b.reassign(variable: result, value: res)
                    },
                    {
                        let match = b.getProperty("match", of: symbol)
                        let res = b.callComputedMethod(match, on: regex, withArgs: [subject])
                        b.reassign(variable: result, value: res)
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
                        b.reassign(variable: result, value: res)
                    },
                    {
                        let search = b.getProperty("search", of: symbol)
                        let res = b.callComputedMethod(search, on: regex, withArgs: [subject])
                        b.reassign(variable: result, value: res)
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
                        b.reassign(variable: result, value: res)
                    },
                    {
                        let matchAll = b.getProperty("matchAll", of: symbol)
                        let res = b.callComputedMethod(matchAll, on: regex, withArgs: [subject])
                        b.reassign(variable: result, value: res)
                    },
                    {
                        let replaceAll = b.getProperty("replaceAll", of: symbol)
                        let res = b.callComputedMethod(replaceAll, on: regex, withArgs: [
                            subject, b.loadString(b.randomString()),
                        ])
                        b.reassign(variable: result, value: res)
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
        (ForceSpidermonkeyIonGenerator,    10),
        (IonDisableGenerator,               5),
        (RelazifyFunctionsGenerator,        5),
        (TrialInlineGenerator,              5),
        (GcGenerator,                      10),
        (MinorGcGenerator,                  5),
        (MaybeGcGenerator,                  5),
        (IncrementalGcGenerator,            5),
        (GcZealGenerator,                   5),
        (SpidermonkeyStringShapeGenerator, 10),
        (JobQueueGenerator,                 5),
        (JitCompilerOptionGenerator,        3),
        (WatchtowerGenerator,               5),
        (ObjectFuseGenerator,               5),
        (GCParamGenerator,                  4),
        (BailoutStormGenerator,             4),
        (GeneratorResumeGenerator,          8),
        (AsyncResumeGenerator,              8),
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
        "gczeal": .function([.opt(.integer | .string), .opt(.integer)] => (.undefined | .integer)),
        "unsetgczeal": .function([.oneof(.integer, .string)] => .undefined),
        "schedulezone": .function([.jsAnything] => .undefined),
        "startgc": .function([.opt(.integer), .opt(.string)] => .undefined),
        "gcslice": .function([.opt(.integer), .opt(.object())] => .undefined),
        "finishgc": .function([] => .undefined),
        "abortgc": .function([] => .undefined),
        "gcstate": .function([.opt(.object())] => .string),
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
        "getWaitForAllPromise": .function([.object()] => .jsPromise()),
        "resolvePromise": .function([.object(), .jsAnything] => .undefined),
        "rejectPromise": .function([.object(), .jsAnything] => .undefined),
        "gcparam": .function([.string, .opt(.number)] => (.number | .undefined)),
        // "setJitCompilerOption": .function([.string, .number] => .undefined),
        // "getJitCompilerOptions": .function([] => .object()),
        "addObjectFuse": .function([.object()] => .undefined),
        "getObjectFuseState": .function([.object()] => .object()),
        "newRope": .function([.string, .string, .opt(.object())] => .string),
        "isRope": .function([.string] => .boolean),
        "safeResolvePromise": .function([.object(), .jsAnything] => .undefined),
        "verifyprebarriers": .function([] => .undefined),
        "fullcompartmentchecks": .function([.boolean] => .undefined),
        "gcPreserveCode": .function([] => .undefined),
        "setMarkStackLimit": .function([.number] => .undefined),
        "selectforgc": .function([] => .undefined),
        "enableOsiPointRegisterChecks": .function([] => .undefined),
        "makeFinalizeObserver": .function([] => .object()),
        "finalizeCount": .function([] => .number),
        "representativeStringArray": .function([] => .jsArray),
        "displayName": .function([.function()] => .string),
        "hasInvalidatedTeleporting": .function([.object()] => .boolean),
    ],

    additionalObjectGroups: [],

    additionalEnumerations: [],

    additionalOptionsBags: [],

    optionalPostProcessor: nil
)
