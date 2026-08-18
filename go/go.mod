// The module path is the DOWNLOAD ADDRESS — `go get` fetches exactly this URL,
// so it must match the public mirror repository byte for byte. The SDK lives in
// the repo's go/ subdirectory, which is why the path carries the /go suffix and
// why its release tags are `go/vX.Y.Z` rather than bare `vX.Y.Z`.
module github.com/Misar-AI/misarreach-sdks/go/v5

go 1.22
