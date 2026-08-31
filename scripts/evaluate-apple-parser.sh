#!/bin/sh
set -eu
parser_repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
parser_build=$(mktemp -d /tmp/whoops-apple-eval.XXXXXX)
cd "$parser_repository"
xcrun swiftc -parse-as-library -swift-version 6 -O \
  ios/WhoopsApp/WhoopsApp/Domain/Models/AppError.swift \
  ios/WhoopsApp/WhoopsApp/Domain/Models/AssessmentModels.swift \
  ios/WhoopsApp/WhoopsApp/Domain/Models/WorkoutModels.swift \
  ios/WhoopsApp/WhoopsApp/Domain/Services/VersionedWorkoutParser.swift \
  ios/WhoopsApp/WhoopsApp/Domain/Services/OnDeviceWorkoutParser.swift \
  ios/WhoopsApp/WhoopsApp/Domain/Services/AppleWorkoutModelClient.swift \
  scripts/EvaluateAppleWorkoutParser.swift -o "$parser_build/evaluate"
"$parser_build/evaluate" fixtures/workouts/apple-parser-evaluation.json "$@"
