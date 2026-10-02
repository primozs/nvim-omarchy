-- Agent host workspace must not collide with the editor project workspace.
describe("herd.project_workspace", function()
  local PW = require("herd.project_workspace")

  it("prefixes herd: so float prune cannot close the nvim tab", function()
    local project = PW.project()
    local host = PW.label()
    assert.are.equal("herd:" .. project, host)
    assert.is_true(host ~= project)
  end)
end)
