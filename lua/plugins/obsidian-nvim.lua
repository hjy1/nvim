return {
  "obsidian-nvim/obsidian.nvim",
  lazy = false,
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  opts = {
    legacy_commands = false,

    workspaces = {
      {
        name = "obs",
        path = vim.fn.expand("~/Documents/obs"),
      },
    },

    picker = {
      name = "fzf-lua",
    },
  },

  config = function(_, opts)
    require("obsidian").setup(opts)

    vim.keymap.set("n", "<leader>nn", "<cmd>Obsidian new<cr>", { desc = "New note" })
    vim.keymap.set("n", "<leader>nf", "<cmd>Obsidian quick_switch<cr>", { desc = "Find note" })
    vim.keymap.set("n", "<leader>ns", "<cmd>Obsidian search<cr>", { desc = "Search notes" })
    vim.keymap.set("n", "<leader>nt", "<cmd>Obsidian today<cr>", { desc = "Today's daily note" })
  end,
}
