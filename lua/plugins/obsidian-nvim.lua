return {
	"https://github.com/obsidian-nvim/obsidian.nvim",
	lazy = false,
	config = function()
		require("obsidian").setup({
			legacy_commands = false,
			workspaces = { { name = "Notes", path = "/run/media/veracrypt64/Notes/" } },
			picker = { name = "fzf-lua" },
		})

		vim.keymap.set("n", "<leader>nn", "<cmd>Obsidian new<cr>", { desc = "New Note" })
		vim.keymap.set("n", "<leader>nf", "<cmd>Obsidian quick_switch<cr>", { desc = "Find note" })
		vim.keymap.set("n", "<leader>ns", "<cmd>Obsidian search<cr>", { desc = "Search notes" })
		vim.keymap.set("n", "<leader>nt", "<cmd>Obsidian today<cr>", { desc = "Today's daily note" })
	end,
}
