return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview (all changes)" },
      { "<leader>gD", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
    },
    -- Register early so lazygit can call it via nvim --remote-expr.
    init = function()
      vim.api.nvim_create_user_command("LazygitDiff", function(args)
        local parts = vim.split(args.args, "%s+", { trimempty = true })
        if #parts == 0 then
          return
        end

        local function is_commit(s)
          return type(s) == "string" and #s >= 7 and s:match("^%x+$") ~= nil
        end

        -- 1 arg: commit hash → whole commit; otherwise → working-tree file
        -- 2+ args: commit + file
        local commit, file
        if #parts == 1 then
          if is_commit(parts[1]) then
            commit = parts[1]
          else
            file = parts[1]
          end
        else
          commit = parts[1]
          file = table.concat(parts, " ", 2)
        end

        -- remote-expr runs mid-event; defer UI work to the next tick.
        vim.schedule(function()
          for _, term in ipairs(Snacks.terminal.list()) do
            if term:valid() then
              term:hide()
            end
          end

          require("lazy").load({ plugins = { "diffview.nvim" } })

          local cmd
          if commit and file then
            local root = LazyVim.root.git()
            local path = vim.fn.fnamemodify(file, ":p")
            if root and vim.fn.fnamemodify(path, ":h") == vim.fn.getcwd() then
              path = vim.fn.fnamemodify(root .. "/" .. file, ":p")
            end
            cmd = "DiffviewOpen " .. commit .. "^! -- " .. vim.fn.fnameescape(path)
          elseif commit then
            cmd = "DiffviewOpen " .. commit .. "^!"
          else
            local root = LazyVim.root.git()
            local path = vim.fn.fnamemodify(file, ":p")
            if root and vim.fn.fnamemodify(path, ":h") == vim.fn.getcwd() then
              path = vim.fn.fnamemodify(root .. "/" .. file, ":p")
            end
            cmd = "DiffviewOpen -- " .. vim.fn.fnameescape(path)
          end

          pcall(vim.cmd, "DiffviewClose")
          vim.cmd(cmd)
        end)
      end, { nargs = "+", complete = "file", force = true })
    end,
    opts = {
      view = {
        default = {
          layout = "diff2_horizontal",
        },
      },
      keymaps = {
        view = {
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close diffview" } },
        },
        file_panel = {
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close diffview" } },
        },
      },
    },
  },
}
