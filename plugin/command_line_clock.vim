" Maintain a clock in the command line window
" Author: Landon Bouma <https://tallybark.com/>
" Online: https://github.com/landonb/vim-command-line-clock
" License: https://creativecommons.org/publicdomain/zero/1.0/
"  vim:tw=0:ts=2:sw=2:et:norl:ft=vim
" Copyright © 2021 Landon Bouma.

" Age-old answer to Quelle heure est il on a mac with no menu bar.

" See also plugin to show the time of day and date in the title bar:
"
"     https://github.com/landonb/vim-title-bar-time-of-day

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

" YOU: Uncomment next 'unlet', then <F9> to reload this file.
"      (Iff: https://github.com/landonb/vim-source-reloader)
"
" silent! unlet g:loaded_plugin_command_line_clock

if exists('g:loaded_plugin_command_line_clock') || &cp || v:version < 800
    finish
endif

let g:loaded_plugin_command_line_clock = 1

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

" Ref:
"
"   :h cmdline-editing for help on command-line mode and command-line window.

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

" Timer ID, which would never be called except on <F9> plug reload.
let s:timer = 0

function! s:StopTheClock()
  if ! exists('s:timer') || ! s:timer | return | endif

  echom "Stopping timer: " . s:timer
  call timer_stop(s:timer)
  let s:timer = 0
endfunction

function! s:StartTheClock()
  call s:StopTheClock()

  " Guard clause: Users opt-out by setting g:CommandLineClockDisabled truthy.
  if exists('g:CommandLineClockDisabled') && g:CommandLineClockDisabled
    return
  endif

  " Timer repeat time, configurable via g:CommandLineClockRepeatTime.
  " - The timer delay determines the longest length of time after the clock
  "   time changes that the user might have to wait until the clock updates.
  " - The timer delay also determines how quickly the clock repaints on shift-
  "   selecting, if you use the landonb/vim-select-mode-stopped-down plugin,
  "   which has a kludgey blank 'echo' to avoid the @/ being echoed -- which
  "   clears the command window briefly before the clock is repainted.
  " - Time repeat time value research:
  "   - I set g:CommandLineClockRepeatTime as low as 5, but I see the same
  "     quick flicker that I do when it's higher, at 101 msec.
  "     - But at 1010 msec. it's no longer a flicker, the clock disappears
  "       for a brief moment every time you advance the visual selection
  "       (e.g., holding Shift and pressing Ctrl-arrow).
  "     - 202 msec. is also perceptible. But not so much 153 msec.
  "       Obviously, the OS is not firing exactly at that interval,
  "       but it gives us a ballpark.
  "     - Based on this empirical evidence, and because 101 is the boss,
  "       choosing 101, paired with a 50 backoff (e.g., wait 5 sec. before
  "       overwriting command line with latest clock time).
  "   - All the values I demoed (incl. BackoffMultiplier, from next section):
  "
  "       let g:CommandLineClockRepeatTime = 1010
  "       let g:CommandLineClockBackoffMultiplier = 5
  "
  "       let g:CommandLineClockRepeatTime = 202
  "       let g:CommandLineClockBackoffMultiplier = 25
  "
  "       let g:CommandLineClockRepeatTime = 153
  "       let g:CommandLineClockBackoffMultiplier = 33
  "
  "       " Jussssst right.
  "       let g:CommandLineClockRepeatTime = 101
  "       let g:CommandLineClockBackoffMultiplier = 50
  "
  "       let g:CommandLineClockRepeatTime = 50
  "       let g:CommandLineClockBackoffMultiplier = 101
  "
  "       let g:CommandLineClockRepeatTime = 5
  "       let g:CommandLineClockBackoffMultiplier = 1010
  "
  if !exists('g:CommandLineClockRepeatTime')
    " 2021-02-07: Now I'm not so sure, 101 is generally fine,
    " but 50 does better when scrolling, for which there is
    " no autocommand (WinScrolled?). At 101, when scrolling,
    " the flicker is noticeable -- the clock disappears for
    " up to 100 msec., which is very perceivable. At 50, it
    " redraws much more noticeably quicker, still a flicker,
    " but more a flicker and less a slow on off on off. And
    " at 5, it's a very fast flicker. / Though when I compare
    " how it looks when I'm not staring at the clock -- out of
    " the corner of my eye, how I'll usually experience it --
    " then I cannot really tell a difference between 'em.
    let g:CommandLineClockRepeatTime = 101
    "  let g:CommandLineClockRepeatTime = 50
    "  let g:CommandLineClockRepeatTime = 5
  endif

  " The back-off multiplier represents how long to wait after a new message
  " is detected before repainting the clock (and overwriting the message).
  " This is suppose to give the user time to see (and read) whatever new
  " message arrived. The value is represented as a multipler of the timer
  " repeat time so that we don't have to use more than the one timer, which
  " we treat as somewhat of a clock tick (though in reality I don't know that
  " Vim promises the timer is called on time, so there could easily be some
  " drift in the approximation).
  " - tl;dr The time until repaint after a new message is detected is
  "   determined by this BackoffMultiplier multiplied by the RepeatTime.
  if !exists('g:CommandLineClockBackoffMultiplier')
    let g:CommandLineClockBackoffMultiplier = 50
    "  let g:CommandLineClockBackoffMultiplier = 101
    "  let g:CommandLineClockBackoffMultiplier = 1010
  endif

  let s:timer = timer_start(g:CommandLineClockRepeatTime, 'CommandLineClockPaint', { 'repeat': -1 })
endfunction

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

" When a new message is detected and this plugin needs to wait to repaint
" the clock, the s:new_message_backoff_count is set to the repeat time,
" g:CommandLineClockRepeatTime, and is used to count down to when it's
" okay to paint again.
let s:new_message_backoff_count = 0

" Avoid calling `echo` unnecessarily on every timer event, lest the command
" line flicker (sorta; at least on Mint MATE 19.3, it looks like the top of
" a line of characters, possibly the buffer filename, e.g.,
"   plugin/command_line_clock.vim" 197L, 7795C
" is printed but then quickly overwritten).
" Track the previous date time that was echoed to avoid echoing again
" until the clock time changes, or until we know we have to repaint.
let s:previous_clock_datetime = ''

let s:first_time_through = 1

function! CommandLineClockPaint(timer)

  if s:first_time_through == 1
    " On MacVim, do not call `echo` when first run on startup, else Vim prompts
    " (via the command window): 'Press ENTER or type command to continue'.
    let s:first_time_through = 0
    return
  endif

  " Scrolling the window clears the command line but is not a watchable event
  " (though there is a feature request for a 'WinScrolled' autocommand), so we
  " have to manually check (poll on every timer event).
  call EnsureRepaintsIfWindowScrolled()

  " +++

  " Bouncer Clause #1 (aka Guard Clause):
  " Use backoff countdown to avoid clobbering new messages too quickly.
  " - Note that we always check s:new_message_backoff_count first so that we
  "   always decrement the backoff count on each clock tick/timer event.
  if s:new_message_backoff_count > 0
    let s:new_message_backoff_count -= 1
    return
  endif

  " +++

  " Guard Clause #2: Only update clock in Normal and Insert mode.
  " - E.g., if dubs_grep_steady is installed and user pressed `\g` to search,
  "   Vim waits for user input in the command window (mode() ==# 'c').
  "   If we :echo'ed during this time, it would scroll up the command
  "   window input prompt and otherwise mess with the user.
  if mode() !=# 'n' && mode() !=# 'i' && mode() !=# 's' | return | endif

  " +++

  let l:clock_day = strftime('%Y-%m-%d')
  let l:clock_hours = strftime('%H:%M')
  let l:clock_datetime = printf('%s %s', l:clock_day, l:clock_hours)

  " +++

  " Guard Clause #3: Avoid repeating same clock time to avoid over-
  " echoing and causing command line artifacts.
  if l:clock_datetime == s:previous_clock_datetime | return | endif

  " +++

  " MAYBE/2021-02-01: Make optional: right-alignment and padding from edge.
  " - Currently, right-aligned with no padding.
  "     let l:cols = &columns - 1
  " - Scratch that, right-aligned with 1 character padding.
  let l:cols = &columns - 2

  " The %{width}S right-aligns a string in the indicated width.
  exec "echo printf('%" . l:cols . "S', '" . l:clock_datetime . "')"

  let s:previous_clock_datetime = l:clock_datetime
endfunction

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

" The command line is cleared when the user scrolls the window, e.g., using the
" mouse wheel, or Ctrl-y or Ctrl-e (or Ctrl-Up/-Down from dubs_edit_juice.vim).
"
" Except that Vim does not send an event on scroll.
"
" So here we determine if the window was scrolled since last we checked.
"
" - Note that a WinScrolled event was recently (2020) added to NeoVim:
"     *Implement scroll autocommand* https://github.com/neovim/neovim/pull/13117
" - And for Vim there are at least two such issues asking for the same:
"     *The window scroll event*           https://github.com/vim/vim/issues/5181
"     *Feat. Req: screen scroll autocmd*  https://github.com/vim/vim/issues/3127
"
" - See also CursorMoved/CursorMovedI, but hooking these won't
"   help when the user scrolls *without* moving the cursor.
"
" Caveat: Until WinScrolled is available, note that:
"
"           Scrolling causes the clock to flicker!
"

let s:cursorLineNr = 0
let s:firstVisibleLineNr = 0
let s:lastVisibleLineNr = 0

function! EnsureRepaintsIfWindowScrolled()
  let l:cursorLineNr = line(".")
  let l:firstVisibleLineNr = line("w0")
  let l:lastVisibleLineNr = line("w$")

  if (l:cursorLineNr != s:cursorLineNr)
    \ || (l:firstVisibleLineNr != s:firstVisibleLineNr)
    \ || (l:lastVisibleLineNr != s:lastVisibleLineNr)
    " Window was scrolled, so command window was cleared,
    " so clear previous clock state to force a repaint.
    let s:previous_clock_datetime = ''
  endif

  let s:cursorLineNr = l:cursorLineNr
  let s:firstVisibleLineNr = l:firstVisibleLineNr
  let s:lastVisibleLineNr = l:lastVisibleLineNr
endfunction

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

" Use the CmdlineChanged event to enable the backoff timeout, to avoid
" clobbering a newly written message before the user has had time to
" read it.
"
" But note that CmdlineChanged is not 100% inclusive. For instance,
" scrolling the window clears the command line window, but that does
" not tickle CmdlineChanged, and there's otherwise no autocommand for
" scroll (though see 'WinScrolled' feature request, mentioned above).
" But we also cannot read what's in the command window, so this is the
" best we've got.

function! s:CreateEventHandlers()
  augroup command_line_clock_autocommands
    autocmd!
    autocmd CmdlineChanged *
      \ let s:new_message_backoff_count = g:CommandLineClockBackoffMultiplier
      \ | let s:previous_clock_datetime = ''
  augroup END
endfunction

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

call s:CreateEventHandlers()

call s:StartTheClock()

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

