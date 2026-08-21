import Crap4SwiftCore
import Foundation

let application = CliApplication()
let status = application.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(status)
