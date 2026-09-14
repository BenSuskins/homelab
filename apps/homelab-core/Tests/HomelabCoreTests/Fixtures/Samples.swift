import Foundation

/// Trimmed but otherwise verbatim GitHub output. Field names and value shapes
/// match the real API so the decoding under test is the decoding that ships —
/// including GraphQL's `data` → `repository` → `pullRequests` → `nodes`
/// nesting, which `gh api graphql` passes through unchanged.
enum Samples {
    static func workflowRuns(
        identifier: Int = 1001,
        status: String,
        conclusion: String?
    ) -> String {
        let conclusionField = conclusion.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "total_count": 1,
          "workflow_runs": [
            {
              "id": \(identifier),
              "name": "Update Homelab",
              "head_branch": "main",
              "status": "\(status)",
              "conclusion": \(conclusionField),
              "html_url": "https://github.com/BenSuskins/homelab/actions/runs/\(identifier)",
              "run_started_at": "2026-08-09T10:00:00Z",
              "updated_at": "2026-08-09T10:04:01Z"
            }
          ]
        }
        """
    }

    static let noWorkflowRuns = """
    { "total_count": 0, "workflow_runs": [] }
    """

    static let pullRequests = """
    {
      "data": {
        "repository": {
          "pullRequests": {
            "nodes": [
              {
                "number": 141,
                "title": "chore(deps): update ansible docker images (major)",
                "author": { "login": "app/renovate" },
                "isDraft": false,
                "mergeable": "MERGEABLE",
                "createdAt": "2026-08-06T09:15:00Z",
                "url": "https://github.com/BenSuskins/homelab/pull/141"
              },
              {
                "number": 139,
                "title": "Add Faro frontend observability",
                "author": null,
                "isDraft": true,
                "mergeable": "CONFLICTING",
                "createdAt": "2026-08-01T09:15:00Z",
                "url": "https://github.com/BenSuskins/homelab/pull/139"
              }
            ]
          }
        }
      }
    }
    """

    static let noPullRequests = """
    { "data": { "repository": { "pullRequests": { "nodes": [] } } } }
    """

    /// An instant-query vector. Prometheus encodes each sample as
    /// `[<unix seconds>, "<value as a string>"]`, which is the awkward bit.
    static let gatusResults = """
    {
      "status": "success",
      "data": {
        "resultType": "vector",
        "result": [
          {
            "metric": {
              "__name__": "gatus_results_endpoint_success",
              "key": "media_plex",
              "group": "Media",
              "name": "plex"
            },
            "value": [1757779200, "1"]
          },
          {
            "metric": {
              "__name__": "gatus_results_endpoint_success",
              "key": "media_sonarr",
              "group": "Media",
              "name": "sonarr"
            },
            "value": [1757779200, "0"]
          },
          {
            "metric": {
              "__name__": "gatus_results_endpoint_success",
              "key": "monitoring_grafana",
              "group": "Monitoring",
              "name": "grafana"
            },
            "value": [1757779200, "1"]
          }
        ]
      }
    }
    """

    static let prometheusError = """
    { "status": "error", "errorType": "bad_data", "error": "parse error at char 1" }
    """

    static let lokiQuery = """
    {
      "status": "success",
      "data": {
        "resultType": "streams",
        "result": [
          {
            "stream": {"host": "Docker", "container": "api"},
            "values": [["1757779200000000000", "started"], ["1757779260000000000", "ready"]]
          },
          {
            "stream": {"host": "Media", "container": "worker"},
            "values": [["1757779230000000000", "warning"]]
          }
        ]
      }
    }
    """

    static let lokiLabelValues = """
    {"status":"success","data":["Media","Docker"]}
    """

    /// A page of runs, newest first, as the workflow-runs endpoint returns it.
    /// `statuses` is a list of `(status, conclusion, minutes long)` so a test
    /// can describe a history in one line.
    static func workflowRunPage(
        _ runs: [(status: String, conclusion: String?, minutes: Int)],
        startingAt identifier: Int = 2000
    ) -> String {
        let bodies = runs.enumerated().map { index, run -> String in
            let conclusionField = run.conclusion.map { "\"\($0)\"" } ?? "null"
            let startHour = String(format: "%02d", 10 + index)
            let endMinute = String(format: "%02d", run.minutes)
            return """
            {
              "id": \(identifier + index),
              "name": "Update Homelab",
              "head_branch": "main",
              "status": "\(run.status)",
              "conclusion": \(conclusionField),
              "html_url": "https://github.com/BenSuskins/homelab/actions/runs/\(identifier + index)",
              "run_started_at": "2026-08-0\(1 + index % 8)T\(startHour):00:00Z",
              "updated_at": "2026-08-0\(1 + index % 8)T\(startHour):\(endMinute):00Z"
            }
            """
        }

        return """
        { "total_count": \(runs.count), "workflow_runs": [\(bodies.joined(separator: ","))] }
        """
    }

    static let viewer = """
    {
      "login": "BenSuskins",
      "name": "Ben Suskins",
      "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
      "html_url": "https://github.com/BenSuskins"
    }
    """

    /// A range query's matrix. Each series carries `values`, a list of the same
    /// `[<unix seconds>, "<value>"]` pairs an instant query carries one of —
    /// including a "NaN", which is a gap in the line and not a reading of zero.
    static let nodeLoadMatrix = """
    {
      "status": "success",
      "data": {
        "resultType": "matrix",
        "result": [
          {
            "metric": { "__name__": "node_load1", "host": "Media", "instance": "192.168.0.201:12345" },
            "values": [
              [1757779200, "0.4"],
              [1757779260, "NaN"],
              [1757779320, "1.2"],
              [1757779380, "0.8"]
            ]
          },
          {
            "metric": { "__name__": "node_load1", "host": "Docker" },
            "values": [
              [1757779200, "2.5"],
              [1757779320, "3.5"]
            ]
          }
        ]
      }
    }
    """
}
