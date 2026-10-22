# Sondagem glab 1.36.0

Sondagem local, sem criar ou modificar requests.

## glab version

```text
glab version 1.36.0
```

## glab auth status --help

```text
Verifies and displays information about your authentication state.

This command tests the authentication states of all known GitLab instances in the config file and reports issues if any


USAGE
  glab auth status [flags]

FLAGS
  -h, --hostname string   Check a specific instance's authentication status
  -t, --show-token        Display the auth token

INHERITED FLAGS
  --help   Show help for command

LEARN MORE
  Use 'glab <command> <subcommand> --help' for more information about a command.

```

## glab mr create --help

```text
Create new merge request

USAGE
  glab mr create [flags]

ALIASES
  new

FLAGS
      --allow-collaboration    Allow commits from other members
  -a, --assignee usernames     Assign merge request to people by their usernames
      --copy-issue-labels      Copy labels from issue to the merge request. Used with --related-issue
      --create-source-branch   Create source branch if it does not exist
  -d, --description string     Supply a description for merge request
      --draft                  Mark merge request as a draft
  -f, --fill                   Do not prompt for title/description and just use commit info
      --fill-commit-body       Fill description with each commit body when multiple commits. Can only be used with --fill
  -H, --head OWNER/REPO        Select another head repository using the OWNER/REPO or `GROUP/NAMESPACE/REPO` format or the project ID or full URL
  -l, --label strings          Add label by name. Multiple labels should be comma separated
  -m, --milestone string       The global ID or title of a milestone to assign
      --no-editor              Don't open editor to enter description. If set to true, uses prompt. (default false)
      --push                   Push committed changes after creating merge request. Make sure you have committed changes
      --recover                Save the options to a file if the merge request fails to be created. If the file exists, the options will be loaded from the recovery file (EXPERIMENTAL)
  -i, --related-issue string   Create merge request for an issue. The merge request title will be created from the issue if --title is not provided.
      --remove-source-branch   Remove Source Branch on merge
      --reviewer usernames     Request review from users by their usernames
  -s, --source-branch string   The Branch you are creating the merge request. Default is the current branch.
      --squash-before-merge    Squash commits into a single commit when merging
  -b, --target-branch string   The target or base branch into which you want your code merged
  -t, --title string           Supply a title for merge request
  -w, --web                    continue merge request creation on web browser
      --wip                    Mark merge request as a work in progress. Alternative to --draft
  -y, --yes                    Skip submission confirmation prompt, with --fill it skips all optional prompts

INHERITED FLAGS
      --help              Show help for command
  -R, --repo OWNER/REPO   Select another repository using the OWNER/REPO or `GROUP/NAMESPACE/REPO` format or full URL or git URL

EXAMPLES
  glab mr new
  glab mr create -a username -t "fix annoying bug"
  glab mr create -f --draft --label RFC
  glab mr create --fill --web
  glab mr create --fill --fill-commit-body --yes

LEARN MORE
  Use 'glab <command> <subcommand> --help' for more information about a command.

```

## glab mr view --help

```text
Display the title, body, and other information about a merge request.

USAGE
  glab mr view {<id> | <branch>} [flags]

ALIASES
  show

FLAGS
  -c, --comments       Show mr comments and activities
  -p, --page int       Page number
  -P, --per-page int   Number of items to list per page (default 20)
  -s, --system-logs    Show system activities / logs
  -w, --web            Open mr in a browser. Uses default browser or browser specified in BROWSER variable

INHERITED FLAGS
      --help              Show help for command
  -R, --repo OWNER/REPO   Select another repository using the OWNER/REPO or `GROUP/NAMESPACE/REPO` format or full URL or git URL

LEARN MORE
  Use 'glab <command> <subcommand> --help' for more information about a command.

```

## glab api --help

```text
Makes an authenticated HTTP request to the GitLab API and prints the response.
The endpoint argument should either be a path of a GitLab API v4 endpoint, or 
"graphql" to access the GitLab GraphQL API.

- [GitLab REST API Docs](https://docs.gitlab.com/ee/api/index.html)
- [GitLab GraphQL Docs](https://docs.gitlab.com/ee/api/graphql/)

If the current directory is a Git directory, the GitLab authenticated host in the current 
directory will be used otherwise `gitlab.com` will be used.
Override the GitLab hostname with '--hostname'.

Placeholder values `:fullpath` or `:id`, `:user` or `:username`, `:group`, `:namespace`, 
`:repo`, and `:branch` in the endpoint argument will get replaced with values from the 
repository of the current directory.

The default HTTP request method is "GET" normally and "POST" if any parameters
were added. Override the method with '--method'.

Pass one or more '--raw-field' values in "key=value" format to add
JSON-encoded string parameters to the POST body.

The '--field' flag behaves like '--raw-field' with magic type conversion based
on the format of the value:

- literal values "true", "false", "null", and integer numbers get converted to
  appropriate JSON types;
- placeholder values ":namespace", ":repo", and ":branch" get populated with values
  from the repository of the current directory;
- if the value starts with "@", the rest of the value is interpreted as a
  filename to read the value from. Pass "-" to read from standard input.

For GraphQL requests, all fields other than "query" and "operationName" are
interpreted as GraphQL variables.

Raw request body may be passed from the outside via a file specified by '--input'.
Pass "-" to read from standard input. In this mode, parameters specified via
`--field` flags are serialized into URL query parameters.

In '--paginate' mode, all pages of results will sequentially be requested until
there are no more pages of results. For GraphQL requests, this requires that the
original query accepts an '$endCursor: String' variable and that it fetches the
`pageInfo{ hasNextPage, endCursor }` set of fields from a collection.


USAGE
  glab api <endpoint> [flags]

FLAGS
  -F, --field stringArray       Add a parameter of inferred type (changes default HTTP method to "POST")
  -H, --header stringArray      Add an additional HTTP request header
      --hostname string         The GitLab hostname for the request (default is "gitlab.com" or authenticated host in current git directory)
  -i, --include                 Include HTTP response headers in the output
      --input string            The file to use as body for the HTTP request
  -X, --method string           The HTTP method for the request (default "GET")
      --paginate                Make additional HTTP requests to fetch all pages of results
  -f, --raw-field stringArray   Add a string parameter
      --silent                  Do not print the response body

INHERITED FLAGS
  --help   Show help for command

EXAMPLES
  $ glab api projects/:fullpath/releases
  
  $ glab api projects/gitlab-com%2Fwww-gitlab-com/issues
  
  $ glab api issues --paginate
  
  $ glab api graphql -f query='
    query {
      project(fullPath: "gitlab-org/gitlab-docs") {
        name
        forksCount
        statistics {
          wikiSize
        }
        issuesEnabled
        boards {
          nodes {
            id
            name
          }
        }
      }
    }
  '
  
  $ glab api graphql --paginate -f query='
    query($endCursor: String) {
      project(fullPath: "gitlab-org/graphql-sandbox") {
        name
        issues(first: 2, after: $endCursor) {
          edges {
            node {
              title
            }
          }
          pageInfo {
            endCursor
            hasNextPage
          }
        }
      }
    }'

ENVIRONMENT VARIABLES
  GITLAB_TOKEN, OAUTH_TOKEN (in order of precedence): an authentication token for API requests.
  GITLAB_HOST, GITLAB_URI, GITLAB_URL: specify a GitLab host to make request to.

LEARN MORE
  Use 'glab <command> <subcommand> --help' for more information about a command.

```

## glab mr merge --help

```text
Merge/Accept merge requests

USAGE
  glab mr merge {<id> | <branch>} [flags]

ALIASES
  accept

FLAGS
      --auto-merge              Set auto-merge (default true)
  -m, --message string          Custom merge commit message
  -r, --rebase                  Rebase the commits onto the base branch
  -d, --remove-source-branch    Remove source branch on merge
      --sha string              Merge Commit sha
  -s, --squash                  Squash commits on merge
      --squash-message string   Custom Squash commit message
  -y, --yes                     Skip submission confirmation prompt

INHERITED FLAGS
      --help              Show help for command
  -R, --repo OWNER/REPO   Select another repository using the OWNER/REPO or `GROUP/NAMESPACE/REPO` format or full URL or git URL

EXAMPLES
  glab mr merge 235
  glab mr accept 235
  glab mr merge    # Finds open merge request from current branch

LEARN MORE
  Use 'glab <command> <subcommand> --help' for more information about a command.

```

## Limitações

A ajuda confirma flags e paginação. Os campos JSON e o comportamento de merge agendado exigem um MR real autenticado; não foram confirmados nesta sondagem.

## Verificações adicionais

`glab mr view --output json 1` falhou com `unknown flag: --output`.
`glab auth status --hostname gitlab.com` informa `Invalid token provided`.
Nenhum token foi copiado para este registro. R3–R6 aguardam uma sondagem
autenticada; nenhuma operação de criação ou merge foi executada.
