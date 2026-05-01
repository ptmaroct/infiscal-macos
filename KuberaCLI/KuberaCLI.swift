import ArgumentParser
import Foundation
import KuberaCore

@main
struct Kubera: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kubera",
        abstract: "Manage Infisical secrets configured for Kubera from the command line.",
        version: "1.5.1-beta.2",
        subcommands: [
            Status.self,
            Login.self,
            Logout.self,
            Config.self,
            Projects.self,
            Envs.self,
            List.self,
            Get.self,
            Info.self,
            Copy.self,
            Set.self,
            Remove.self,
            Export.self,
            Import.self,
            Run.self,
            Tags.self,
            Open.self,
        ]
    )
}
