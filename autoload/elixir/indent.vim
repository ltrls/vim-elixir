if !exists("g:elixir_indent_max_lookbehind")
  let g:elixir_indent_max_lookbehind = 30
endif

" Return the effective value of 'shiftwidth'
function! s:sw()
  return &shiftwidth == 0 ? &tabstop : &shiftwidth
endfunction

function! elixir#indent#indent(lnum)
  let lnum = a:lnum
  let text = getline(lnum)
  let prev_nb_lnum = prevnonblank(lnum-1)
  let prev_nb_text = getline(prev_nb_lnum)

  call s:debug("==> Indenting line " . lnum)
  call s:debug("text = '" . text . "'")

  let [_, curs_lnum, curs_col, _] = getpos('.')
  call cursor(lnum, 0)

  let handlers = [
        \'top_of_file',
        \'following_trailing_binary_operator',
        \'starts_with_pipe',
        \'starts_with_binary_operator',
        \'inside_block',
        \'starts_with_end',
        \'inside_generic_block',
        \'follow_prev_nb'
        \]
  for handler in handlers
    call s:debug('testing handler elixir#indent#handle_'.handler)
    let context = {'lnum': lnum, 'text': text, 'prev_nb_lnum': prev_nb_lnum, 'prev_nb_text': prev_nb_text}
    let indent = function('elixir#indent#handle_'.handler)(context)
    if indent != -1
      call s:debug('line '.lnum.': elixir#indent#handle_'.handler.' returned '.indent)
      call cursor(curs_lnum, curs_col)
      return indent
    endif
  endfor

  call s:debug("defaulting")
  call cursor(curs_lnum, curs_col)
  return 0
endfunction

function! s:debug(str)
  if exists("g:elixir_indent_debug") && g:elixir_indent_debug
    echom a:str
  endif
endfunction

function! s:starts_with(context, expr)
  return s:_starts_with(a:context.text, a:expr, a:context.lnum)
endfunction

function! s:prev_starts_with(context, expr)
  return s:_starts_with(a:context.prev_nb_text, a:expr, a:context.prev_nb_lnum)
endfunction

" Returns 0 or 1 based on whether or not the text starts with the given
" expression and is not a string or comment
function! s:_starts_with(text, expr, lnum)
  let pos = match(a:text, '^\s*'.a:expr)
  if pos == -1
    return 0
  else
    " NOTE: @jbodah 2017-02-24: pos is the index of the match which is
    " zero-indexed. Add one to make it the column number
    if s:is_string_or_comment(a:lnum, pos + 1)
      return 0
    else
      return 1
    end
  end
endfunction

function! s:prev_ends_with(context, expr)
  return s:_ends_with(a:context.prev_nb_text, a:expr, a:context.prev_nb_lnum)
endfunction

" Returns 0 or 1 based on whether or not the text ends with the given
" expression and is not a string or comment
function! s:_ends_with(text, expr, lnum)
  let pos = match(a:text, a:expr.'\s*$')
  if pos == -1
    return 0
  else
    if s:is_string_or_comment(a:lnum, pos)
      return 0
    else
      return 1
    end
  end
endfunction

" Returns 0 or 1 based on whether or not the given line number and column
" number pair is a string or comment
function! s:is_string_or_comment(line, col)
  return synIDattr(synID(a:line, a:col, 1), "name") =~ '\%(String\|Comment\)'
endfunction

" Skip expression for searchpair. Returns 0 or 1 based on whether the value
" under the cursor is a string or comment
function! elixir#indent#searchpair_back_skip()
  " NOTE: @jbodah 2017-02-27: for some reason this function gets called with
  " and index that doesn't exist in the line sometimes. Detect and account for
  " that situation
  let curr_col = col('.')
  if getline('.')[curr_col-1] == ''
    let curr_col = curr_col-1
  endif
  return s:is_string_or_comment(line('.'), curr_col)
endfunction

" DRY up regex for keywords that 1) makes sure we only look at complete words
" and 2) ignores atoms
function! s:keyword(expr)
  return ':\@<!\<\C\%('.a:expr.'\)\>:\@!'
endfunction

" Start at the end of text and search backwards looking for a match. Also peek
" ahead if we get a match to make sure we get a complete match. This means
" that the result should be the position of the start of the right-most match
function! s:find_last_pos(lnum, text, match)
  let last = len(a:text) - 1
  let c = last

  while c >= 0
    let substr = strpart(a:text, c, last)
    let peek = strpart(a:text, c - 1, last)
    let ss_match = match(substr, a:match)
    if ss_match != -1
      let peek_match = match(peek, a:match)
      if peek_match == ss_match + 1
        let syng = synIDattr(synID(a:lnum, c + ss_match, 1), 'name')
        if syng !~ '\%(String\|Comment\)'
          return c + ss_match
        end
      end
    end
    let c -= 1
  endwhile

  return -1
endfunction

function! elixir#indent#handle_top_of_file(context)
  if a:context.prev_nb_lnum == 0
    return 0
  else
    return -1
  end
endfunction

function! elixir#indent#handle_follow_prev_nb(context)
  return s:get_base_indent(a:context.prev_nb_lnum, a:context.prev_nb_text)
endfunction

" Given the line at `lnum`, returns the indent of the line that acts as the 'base indent'
" for this line. In particular it traverses backwards up things like pipelines
" to find the beginning of the expression
function! s:get_base_indent(lnum, text)
  let prev_nb_lnum = prevnonblank(a:lnum - 1)
  let prev_nb_text = getline(prev_nb_lnum)

  let binary_operator = '\%(=\|<>\|>>>\|<=\|||\|+\|\~\~\~\|-\|&&\|<<<\|/\|\^\^\^\|\*\)'
  let data_structure_close = '\%(\]\|}\|)\)'
  let pipe = '|>'

  if s:_starts_with(a:text, binary_operator, a:lnum)
    return s:get_base_indent(prev_nb_lnum, prev_nb_text)
  elseif s:_starts_with(a:text, pipe, a:lnum)
    return s:get_base_indent(prev_nb_lnum, prev_nb_text)
  elseif s:_ends_with(prev_nb_text, binary_operator, prev_nb_lnum)
    return s:get_base_indent(prev_nb_lnum, prev_nb_text)
  elseif s:_ends_with(a:text, data_structure_close, a:lnum)
    let data_structure_open = '\%(\[\|{\|(\)'
    let close_match_idx = match(a:text, data_structure_close . '\s*$')
    call cursor(a:lnum, close_match_idx + 1)
    let [open_match_lnum, open_match_col] = searchpairpos(data_structure_open, '', data_structure_close, 'bnW')
    let open_match_text = getline(open_match_lnum)
    return s:get_base_indent(open_match_lnum, open_match_text)
  else
    return indent(a:lnum)
  endif
endfunction

function! elixir#indent#handle_following_trailing_binary_operator(context)
  let binary_operator = '\%(=\|<>\|>>>\|<=\|||\|+\|\~\~\~\|-\|&&\|<<<\|/\|\^\^\^\|\*\)'

  if s:prev_ends_with(a:context, binary_operator)
    return indent(a:context.prev_nb_lnum) + s:sw()
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_starts_with_pipe(context)
  if s:starts_with(a:context, '|>')
    let match_operator = '\%(!\|=\|<\|>\)\@<!=\%(=\|>\|\~\)\@!'
    let pos = s:find_last_pos(a:context.prev_nb_lnum, a:context.prev_nb_text, match_operator)
    if pos == -1
      return indent(a:context.prev_nb_lnum)
    else
      let next_word_pos = match(strpart(a:context.prev_nb_text, pos+1, len(a:context.prev_nb_text)-1), '\S')
      if next_word_pos == -1
        return indent(a:context.prev_nb_lnum) + s:sw()
      else
        return pos + 1 + next_word_pos
      end
    end
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_starts_with_end(context)
  if s:starts_with(a:context, s:keyword('end'))
    let pair_lnum = searchpair(s:keyword('do\|fn'), '', s:keyword('end').'\zs', 'bnW', "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip()")
    return indent(pair_lnum)
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_starts_with_binary_operator(context)
  let binary_operator = '\%(=\|<>\|>>>\|<=\|||\|+\|\~\~\~\|-\|&&\|<<<\|/\|\^\^\^\|\*\)'

  if s:starts_with(a:context, binary_operator)
    let match_operator = '\%(!\|=\|<\|>\)\@<!=\%(=\|>\|\~\)\@!'
    let pos = s:find_last_pos(a:context.prev_nb_lnum, a:context.prev_nb_text, match_operator)
    if pos == -1
      return indent(a:context.prev_nb_lnum)
    else
      let next_word_pos = match(strpart(a:context.prev_nb_text, pos+1, len(a:context.prev_nb_text)-1), '\S')
      if next_word_pos == -1
        return indent(a:context.prev_nb_lnum) + s:sw()
      else
        return pos + 1 + next_word_pos
      end
    end
  else
    return -1
  endif
endfunction

" To handle nested structures properly we need to find the innermost
" nested structure. For example, we might be in a function in a map in a
" function, etc... so we need to first figure out what the innermost structure
" is then forward execution to the proper handler
function! elixir#indent#handle_inside_block(context)
  let start_pattern = '\C\%(\<with\>\|\<if\>\|\<case\>\|\<cond\>\|\<try\>\|\<receive\>\|\<fn\>\|{\|\[\|(\)'
  let end_pattern = '\C\%(\<end\>\|\]\|}\|)\)'
  " hack - handle do: better
  let pair_info = searchpairpos(start_pattern, '', end_pattern, 'bnW', "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip() || getline(line('.')) =~ 'do:'", max([0, a:context.lnum - g:elixir_indent_max_lookbehind]))
  let pair_lnum = pair_info[0]
  let pair_col = pair_info[1]
  if pair_lnum != 0 || pair_col != 0
    let pair_text = getline(pair_lnum)
    let pair_char = pair_text[pair_col - 1]

    let config = {
          \'c': {'aligned_clauses': s:keyword('end')},
          \'t': {'aligned_clauses': s:keyword('end\|catch\|rescue\|after')},
          \'r': {'aligned_clauses': s:keyword('end\|after')},
          \'i': {'aligned_clauses': s:keyword('end\|else')},
          \'[': {'aligned_clauses': ']'},
          \'{': {'aligned_clauses': '}'},
          \'(': {'aligned_clauses': ')'}
          \}

    if pair_char == 'w'
      " Handle with
      call s:debug("testing s:do_handle_with")
      return s:do_handle_with(pair_lnum, pair_col, a:context)
    elseif pair_char == 'f'
      " Handle fn
      call s:debug("testing s:do_handle_fn")
      return s:do_handle_fn(pair_lnum, pair_col, a:context)
    elseif has_key(config, pair_char)
      return s:_handle_block(pair_lnum, config[pair_char], a:context)
    else
      " Should never get hit!
      return -1
    end
  else
    return -1
  end
endfunction

function! s:do_handle_with(start_lnum, start_col, context)
  " Determine if in with/do, do/else|end, or else/end
  let start_pattern = '\C\%(\<with\>\|\<else\>\|\<do\>\)'
  let end_pattern = '\C\%(\<end\>\)'
  let pair_info = searchpairpos(start_pattern, '', end_pattern, 'bnW', "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip()")
  let pair_lnum = pair_info[0]
  let pair_col = pair_info[1]

  let pair_text = getline(pair_lnum)
  let pair_char = pair_text[pair_col - 1]

  if s:starts_with(a:context, '\Cdo:')
    call s:debug("current line is do:")
    return a:start_col - 1 + s:sw()
  elseif s:starts_with(a:context, '\Celse:')
    call s:debug("current line is else:")
    return pair_col - 1
  elseif s:starts_with(a:context, '\Cend')
    call s:debug("current line is end")
    return a:start_col - 1
  elseif s:starts_with(a:context, '\C\(\<do\>\|\<else\>\)')
    call s:debug("current line is do/else")
    return a:start_col - 1
  elseif s:_starts_with(pair_text, '\C\(do\|else\):', pair_lnum)
    call s:debug("inside do:/else:")
    return pair_col - 1 + s:sw()
  elseif pair_char == 'w'
    call s:debug("inside with/do")
    return a:start_col + 4
  elseif pair_char == 'd'
    call s:debug("inside do/else|end")
    return a:start_col - 1 + s:sw()
  else
    call s:debug("inside else/end")
    return s:do_handle_pattern_match_block(pair_lnum, a:context)
  end
endfunction

" Implements indent for pattern-matching blocks (e.g. case, fn, with/else)
function! s:do_handle_pattern_match_block(start_lnum, context)
  call s:debug("running s:do_handle_pattern_match_block")
  " hack!
  if a:context.text =~ '\(fn.*\)\@<!->'
    call s:debug("current line contains ->; assuming match definition")
    return indent(a:start_lnum) + s:sw()
  elseif a:context.prev_nb_text =~ '\(fn.*\)\@<!->'
    call s:debug("prev nb line contains ->; assuming first line of match handler")
    return indent(a:context.prev_nb_lnum) + s:sw()
  else
    call s:debug("assuming match handler")
    return max([indent(a:start_lnum) + s:sw(), indent(a:context.prev_nb_lnum)])
  end
endfunction

function! s:do_handle_fn(start_lnum, start_col, context)
  let config = {
        \'aligned_clauses': s:keyword('end'),
        \'match_clauses': s:keyword('catch\|rescue')}

  if s:starts_with(a:context, config.aligned_clauses)
    call s:debug("clause")
    return indent(a:start_lnum)
  elseif s:prev_ends_with(a:context, '->')
    if a:context.prev_nb_lnum == a:start_lnum
      call s:debug("prev line is fn that ends with ->")
      return indent(a:start_lnum) + s:sw()
    else
      call s:debug("prev line ends with -> but is not fn declaration")
      return indent(a:context.prev_nb_lnum) + s:sw()
    endif
  else
    call s:debug("match_clause")
    return s:do_handle_pattern_match_block(a:start_lnum, a:context)
  endif
endfunction

function! s:_handle_block(start_lnum, config, context)
  if s:starts_with(a:context, a:config.aligned_clauses)
    call s:debug("clause")
    return indent(a:start_lnum)
  else
    return s:do_handle_pattern_match_block(a:start_lnum, a:context)
  endif
endfunction

function! elixir#indent#handle_inside_generic_block(context)
  let pair_lnum = searchpair(s:keyword('do\|fn'), '', s:keyword('end'), 'bW', "line('.') == ".a:context.lnum." || s:is_string_or_comment(line('.'), col('.'))", max([0, a:context.lnum - g:elixir_indent_max_lookbehind]))
  if pair_lnum
    " TODO: @jbodah 2017-03-29: this should probably be the case in *all*
    " blocks
    if s:prev_ends_with(a:context, ',')
      return indent(pair_lnum) + 2 * s:sw()
    else
      return indent(pair_lnum) + s:sw()
    endif
  else
    return -1
  endif
endfunction
