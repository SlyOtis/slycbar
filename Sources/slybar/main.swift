import Core
import Foundation
import Space
import Statusline

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "statusline": exit(Statusline.run(Array(args.dropFirst())))
case "space": exit(Space.run(Array(args.dropFirst())))
default: exit(Core.run(args))
}
