import Foundation

/// A workflow this app is allowed to start. The repository holds other
/// workflows; only the three that exist to be run on demand appear here.
public enum DispatchableWorkflow: String, CaseIterable, Sendable, Codable, Identifiable {
    case update = "update.yml"
    case terraform = "terraform.yml"
    case clean = "clean.yml"

    public var id: String { rawValue }
    public var fileName: String { rawValue }

    public var displayName: String {
        switch self {
        case .update: "Update"
        case .terraform: "Terraform"
        case .clean: "Clean"
        }
    }

    public var summary: String {
        switch self {
        case .update: "Ansible across all hosts"
        case .terraform: "Plan and apply all three roots"
        case .clean: "Prune Docker and system files"
        }
    }
}
