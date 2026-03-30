using OpenClaw.Agent.Core;

namespace OpenClaw.Agent.Tests;

public sealed class FileStateStoreTests
{
    [Fact]
    public void Read_ReturnsDefault_WhenFileContainsOnlyNullBytes()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        var path = Path.Combine(dataRoot, "host-state.json");
        File.WriteAllBytes(path, new byte[128]);

        try
        {
            var store = new FileStateStore();
            var result = store.Read<HostStateRecord>(path);

            Assert.Null(result);
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }

    [Fact]
    public void Write_ReplacesExistingFileAtomically()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        var path = Path.Combine(dataRoot, "host-state.json");

        try
        {
            var store = new FileStateStore();
            store.Write(path, new HostStateRecord
            {
                State = AgentState.Running,
                DesiredState = AgentState.Running
            });

            var roundTrip = store.Read<HostStateRecord>(path);

            Assert.NotNull(roundTrip);
            Assert.Equal(AgentState.Running, roundTrip!.State);
            Assert.Empty(Directory.GetFiles(dataRoot, "*.tmp", SearchOption.AllDirectories));
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }
}
