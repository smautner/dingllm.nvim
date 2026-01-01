local M = {}
local Job = require 'plenary.job'
local ns_id = vim.api.nvim_create_namespace 'dingllm'

local function get_api_key(name)
  return os.getenv(name)
end


-- function M.get_lines_until_cursor()
--   local current_buffer = vim.api.nvim_get_current_buf()
--   local current_window = vim.api.nvim_get_current_win()
--   local cursor_position = vim.api.nvim_win_get_cursor(current_window)
--   local row = cursor_position[1]
--   local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)
--   return table.concat(lines, '\n')
-- end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  if vim.fn.mode() == 'V' then
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  if vim.fn.mode() == 'v' then
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end

  if vim.fn.mode() == '\22' then
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    for i = srow, erow do
      table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1])
    end
    return lines
  end
end


-- function M.get_entire_buffer_text()
--   local current_buffer = vim.api.nvim_get_current_buf()
--   -- Get all lines from 0 to -1 (end of buffer), without trailing newline on last line
--   local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, -1, false)
--   return table.concat(lines, '\n')
-- end


function M.get_entire_buffer_text()
  local current_buffer = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, -1, false)
  local text = table.concat(lines, '\n')
  text = text:gsub('<!--%s*.-%s*-->', '')
  return text
end



function M.get_buffer_mark_prompt()

  local current_buffer = vim.api.nvim_get_current_buf()
  local all_lines = vim.api.nvim_buf_get_lines(current_buffer, 0, -1, false)

  local cursor_row_1_indexed = vim.api.nvim_win_get_cursor(0)[1]

  local mark_a_pos = vim.fn.getpos "'a"
  local mark_b_pos = vim.fn.getpos "'b"

  local prompt_start_row_0_indexed
  local prompt_end_row_0_indexed

  -- Determine the start and end rows for the prompt
  local a_is_set = mark_a_pos[2] ~= 0 and mark_a_pos[1] == current_buffer
  local b_is_set = mark_b_pos[2] ~= 0 and mark_b_pos[1] == current_buffer

  if a_is_set and b_is_set then
    prompt_start_row_0_indexed = math.min(mark_a_pos[2], mark_b_pos[2]) - 1
    prompt_end_row_0_indexed = math.max(mark_a_pos[2], mark_b_pos[2]) - 1
  elseif a_is_set then
    prompt_start_row_0_indexed = mark_a_pos[2] - 1
    prompt_end_row_0_indexed = cursor_row_1_indexed - 1
  elseif b_is_set then
    prompt_start_row_0_indexed = cursor_row_1_indexed - 1
    prompt_end_row_0_indexed = mark_b_pos[2] - 1
  else
    -- If no marks, use the current line as the prompt
    prompt_start_row_0_indexed = cursor_row_1_indexed - 1
    prompt_end_row_0_indexed = cursor_row_1_indexed - 1
  end

  local modified_lines = {}
  for i, line in ipairs(all_lines) do
    local current_line_0_indexed = i - 1
    local processed_line = line

    if current_line_0_indexed == prompt_start_row_0_indexed then
      processed_line = '[PROMPT]' .. processed_line
    end
    if current_line_0_indexed == prompt_end_row_0_indexed then
      processed_line = processed_line .. '[END OF PROMPT]'
    end
    table.insert(modified_lines, processed_line)
  end

  text = table.concat(modified_lines, '\n')
  text = text:gsub('<!--%s*.-%s*-->', '')
  return text
end



function M.get_current_line_text()
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_window = vim.api.nvim_get_current_win()
  local cursor_position = vim.api.nvim_win_get_cursor(current_window)
  local row = cursor_position[1]

  -- Get just the current line (row-1 to row), without trailing newline
  local lines = vim.api.nvim_buf_get_lines(current_buffer, row - 1, row, false)
  -- nvim_buf_get_lines returns a table, even for a single line
  return lines[1] or '' -- Return the line or an empty string if somehow the line is nil
end


local preprompt = '### YOU ARE INTERACTING HERE IN THE CONTEXT ###'



function M.make_gemini_spec_curl_args(opts, prompt, system_prompt, context)
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  local url = opts.url .. "/" .. opts.model .. ":streamGenerateContent?alt=sse&key=" .. api_key
  local data = {

	system_instruction = {
      parts = { { text = system_prompt} },
    },
    contents = {
      -- User turn with multiple parts
      {
        role = "user",
        parts = {
          { text = context },
          --{ text = preprompt .. prompt },
        },
      },
    },
  }

  if opts.think == false then
	data.generationConfig = {
		thinkingConfig = {
		 thinkingBudget = 0,
		},
	  }
  end

  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  table.insert(args, url)
  return args
end



function M.make_MIMO_spec_curl_args(opts, prompt, system_prompt, context)
  local url = opts.url
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  local data = {
    model = opts.model,
    messages = {
      { role = 'system', content = system_prompt },
      { role = 'user', content = context .. '\n' .. prompt },
    },
    stream = false,
    temperature = opts.temperature or 0.3,
    top_p = opts.top_p or 0.95,
    max_completion_tokens = opts.max_tokens or 1024,
    thinking = {
      type = opts.think == false and "disabled" or "enabled"
    }
  }
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  table.insert(args, '-H')
  table.insert(args, 'api-key: ' .. api_key)
  table.insert(args, url)
  return args
end







function M.write_string_at_extmark(str, buf_id, extmark_id)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf_id) then
      -- Buffer might have been closed/invalid, exit early
      return
    end

    local extmark = vim.api.nvim_buf_get_extmark_by_id(buf_id, ns_id, extmark_id, { details = false })
    if not extmark then
      -- Extmark might have been deleted, exit early
      return
    end
    local row, col = extmark[1], extmark[2]

    -- Want to be able to remove all inserted text with single undo command, but
    -- not supposed to call 'undojoin' in asyncronous callback.
    local success, err = pcall(vim.cmd, 'undojoin')
    if not success then
      if err:match 'E790' then
        print("Undojoin failed with E790, ignored")
      else
        print("Unexpected error...")
      end
    end

    local lines = vim.split(str, '\n')
    vim.api.nvim_buf_set_text(buf_id, row, col, row, col, lines)
  end)
end

local function get_prompt(opts)
  local replace = opts.replace
  local visual_lines = M.get_visual_selection()
  local prompt = ''

  if visual_lines then
    prompt = table.concat(visual_lines, '\n')
    if replace then
      vim.api.nvim_command 'normal! c'
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    end
  else
    prompt = M.get_current_line_text()
  end

  return prompt
end




function M.handle_anthropic_spec_data(data_stream, buf_id, extmark_id, event_state)
  if event_state == 'content_block_delta' then
    local json = vim.json.decode(data_stream)
    if json.delta and json.delta.text then
      M.write_string_at_extmark(buf_id, json.delta.text, extmark_id)
    end
  end
end

function M.handle_openai_spec_data(data_stream, buf_id, extmark_id)
  if data_stream:match '"delta":' then
    local json = vim.json.decode(data_stream)
    if json.choices and json.choices[1] and json.choices[1].delta then
      local content = json.choices[1].delta.content
      if content then
        M.write_string_at_extmark(content, buf_id, extmark_id)
      end
    end
  end
end




-- Discrete version:
-- https://ai.google.dev/api/generate-content#v1beta.models.generateContent
--
-- Streaming version:
-- https://ai.google.dev/api/generate-content#v1beta.models.streamGenerateContent
function M.handle_gemini_spec_data(data_stream, buf_id, extmark_id)
  if data_stream:match '"candidates":' then
    local json = vim.json.decode(data_stream)
    if json.candidates and json.candidates[1].content and
        json.candidates[1].content.parts[1].text then
      local content = json.candidates[1].content.parts[1].text
      if content then
        M.write_string_at_extmark(content, buf_id, extmark_id)
      end
    end
  end
end



function M.handle_MIMO_spec_data(data_stream, buf_id, extmark_id)
  if data_stream:match '"delta":' then
  local success, json = pcall(vim.json.decode, data_stream)
  if success and json.choices and json.choices[1] and json.choices[1].delta then
    local content = json.choices[1].delta.content
    if content then
      M.write_string_at_extmark(content, buf_id, extmark_id)
    end
  end
end


local active_job = nil

function M.invoke_llm(opts, make_curl_args, handle_data)
  if active_job then
    active_job:shutdown()
  end

  local buf_id = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1] - 1, cursor_pos[2]
  local extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, row, col, {})

  local prompt = get_prompt(opts)
  local system_prompt = opts.system_prompt or "You are a helpful assistant."
  local context = M.get_buffer_mark_prompt()
  local args = make_curl_args(opts, prompt, system_prompt, context)

  active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, data)
      if data:match 'data: ' then
        local raw_json = data:gsub('^data: ', '')
        if raw_json ~= '[DONE]' then
          handle_data(raw_json, buf_id, extmark_id)
        end
      end
    end,
    on_exit = function()
      active_job = nil
    end,
  }

  active_job:start()
    local json = vim.json.decode(data_stream)
    if json.choices and json.choices[1] and json.choices[1].delta then
      local content = json.choices[1].delta.content
      if content then
        M.write_string_at_extmark(content, buf_id, extmark_id)
      end
    end
  end
end






local group = vim.api.nvim_create_augroup('DING_LLM_AutoGroup', { clear = true })
local active_job = nil

local function debug_write(opts, message)
  if opts.debug and opts.debug_path then
    local debug_file = io.open(opts.debug_path, 'a')
    if debug_file then
      debug_file:write(message .. '\n')
      debug_file:close()
    else
      print("Error: Could not open debug log file at path: " .. opts.debug_path)
    end
  end
end





function M.invoke_llm_and_dump_into_editor(opts, make_curl_args_fn, handle_data_fn)
	-- similar to stream into editors, just dumps the text, also ignores the replace flag, just adds 2 new lines below, sets the cursor there and dumps the content

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  local prompt = get_prompt(opts)
  local system_prompt = opts.system_prompt or "You are a helpful assistant."
  local context = M.get_buffer_mark_prompt()
  local buf_id = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row = cursor_pos[1]

  vim.api.nvim_buf_set_lines(buf_id, row, row, false, { "", "" })
  local extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, row + 1, 0, {})
  vim.api.nvim_win_set_cursor(0, { row + 2, 0 })

  local args = make_curl_args_fn(opts, prompt, system_prompt, context)

  active_job = Job:new {
     command = 'curl',
    args = args,
    on_exit = function(j, return_val)
      if return_val == 0 then
        local response = table.concat(j:result(), "\n")
        local success, json = pcall(vim.json.decode, response)
        if success then
          local content = ""
          if json.choices and json.choices[1] and json.choices[1].message then
            content = json.choices[1].message.content
          elseif json.candidates and json.candidates[1].content then
            content = json.candidates[1].content.parts[1].text
          elseif json.content and type(json.content) == "table" then
            content = json.content[1].text
          end
          if content ~= "" then
            M.write_string_at_extmark(content, buf_id, extmark_id)
          end
        end
      end
      active_job = nil
    end,
  }
  active_job:start()
end




function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
  vim.api.nvim_clear_autocmds { group = group }

  local prompt = get_prompt(opts)
  local system_prompt = opts.system_prompt or 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  -- local context = M.get_entire_buffer_text()
  local context = M.get_buffer_mark_prompt()


  local args = make_curl_args_fn(opts, prompt, system_prompt, context)
  local curr_event_state = nil
  local buf_id = vim.api.nvim_get_current_buf()
  local crow, _ = unpack(vim.api.nvim_win_get_cursor(0))
  local stream_end_extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, crow - 1, -1, {})

  -- a few newlines, we dont want it to start writing in the current line
  if not opts.replace then
		M.write_string_at_extmark("\n\n", buf_id, stream_end_extmark_id)
  end


  -- setup a floating window to show status of LLM request
  local buf = vim.api.nvim_create_buf(false, true)
  local width = 20
  local height = 1
  local win_opts = {
    relative = "editor",
    row = 0,
    col = vim.o.columns - width,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = false,
  }

  local win = vim.api.nvim_open_win(buf, false, win_opts)
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NormalFloat')

  local function update_floating_window(message)
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, { message })
    local message_width = vim.fn.strdisplaywidth(message)
    vim.api.nvim_win_set_width(win, message_width)
  end

  local function parse_and_call(line)
    local event = line:match '^event: (.+)$'
    if event then
      curr_event_state = event
      return
    end
    local data_match = line:match '^data: (.+)$'
    if data_match then
      handle_data_fn(data_match, buf_id, stream_end_extmark_id, curr_event_state)
    end
  end

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  -- Write the full curl command to a debug log file if enabled
  local curl_command = table.concat({'curl', unpack(args)}, ' ')
  debug_write(opts, "REQUEST: " .. curl_command)

  local start_time = vim.loop.hrtime()
  update_floating_window("Waiting for LLM...")

  active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      -- TODO: update status window with token count.
      parse_and_call(out)
      debug_write(opts, '\nRESPONSE: on_stdout: ' .. out)
    end,
    on_stderr = function(_, err)
      -- TODO: parse the bytes sent / recv to update floating window here.
      debug_write(opts, '\nRESPONSE: on_stderr: ' .. err)
    end,
    on_exit = function(j, return_val)
      local end_time = vim.loop.hrtime()
      local elapsed_time_ms = (end_time - start_time) / 1000000
      if return_val ~= 0 then
        if return_val ~= nil then
            vim.schedule(function()
                update_floating_window(string.format("Error: %s", tostring(return_val)))
            end)
        end
      else
        vim.schedule(function()
            update_floating_window(string.format("LLM Response took %.2f ms", elapsed_time_ms))
        end)
        local json_string = table.concat(j:result())
        debug_write(opts, '\nRESPONSE full json (retval=' .. return_val .. '): ' .. json_string)
      end

      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end, 2750)
      active_job = nil
    end,
  }

  active_job:start()

  -- dingllm automatically remaps <esc>, i dont like this at all, so i remove it

  -- vim.api.nvim_create_autocmd('User', {
  --   group = group,
  --   pattern = 'DING_LLM_Escape',
  --   callback = function()
  --     if active_job then
  --       active_job:shutdown()
  --       update_floating_window("LLM streaming cancelled!")
  --       vim.defer_fn(function()
  --         vim.api.nvim_win_close(win, true)
  --       end, 2500)
  --       active_job = nil
  --     end
  --   end,
  -- })
  -- vim.api.nvim_set_keymap('n', '<Esc>', ':doautocmd User DING_LLM_Escape<CR>', { noremap = true, silent = true })


  return active_job
end





function M.make_anthropic_spec_curl_args(opts, prompt, system_prompt, context)
  local url = opts.url
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  local data = {
    system = system_prompt,
    messages = {
			{ role = 'user', content = context },
			{ role = 'user', content = preprompt .. prompt }
		},
    model = opts.model,
    stream = true,
    max_tokens = 4096,
  }
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'x-api-key: ' .. api_key)
    table.insert(args, '-H')
    table.insert(args, 'anthropic-version: 2023-06-01')
  end
  table.insert(args, url)
  return args
end

-- function M.make_openai_spec_curl_args(opts, prompt, system_prompt)
--   local url = opts.url
--   local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
--   local data = {
--     messages = { { role = 'system', content = system_prompt }, { role = 'user', content = prompt } },
--     model = opts.model,
--     temperature = 0.7,
--     stream = true,
--   }
--   local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
--   if api_key then
--     table.insert(args, '-H')
--     table.insert(args, 'Authorization: Bearer ' .. api_key)
--   end
--   table.insert(args, url)
--   return args
-- end
--

return M
