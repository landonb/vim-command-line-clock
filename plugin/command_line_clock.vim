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

" Track the last seen message, to try not to clobber a newly minted message
" too soon (i.e., let's not frustrate the user by clobbering new messages).
let s:last_message = ''
" g:CommandLineClockRepeatTime multiplier: How long to wait after another
" message is detected before updating clock.
let s:new_message_backoff_count = 0

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
    let g:CommandLineClockRepeatTime = 101
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
  endif

  let s:timer = timer_start(g:CommandLineClockRepeatTime, 'CommandLineClockPaint', { 'repeat': -1 })
endfunction

function! CommandLineClockPaint(timer)
  " Guard clause: Only update clock in Normal and Insert mode.
  " - E.g., if dubs_grep_ready installed and user pressed `\g` to search,
  "   Vim waits for user input in the command window (mode() ==# 'c').
  "   If we :echo'ed during this time, it slowly scrolls up the command
  "   window input prompt.
  if mode() !=# 'n' && mode() !=# 'i' && mode() !=# 's' | return | endif

  " +++

  " Guard clause: If a more recent message found last in history, we
  " don't know how long that message has been displayed, and if user
  " has had ample time to digest it, so hold off.
  " https://stackoverflow.com/questions/5441697/how-can-i-get-last-echoed-message-in-vimscript
  " Oh, brilliant! :messages takes a *count*!
  redir => l:final_message
  1messages
  redir END
  if l:final_message != s:last_message
    let s:last_message = l:final_message
    if s:last_message != ""
      let s:new_message_backoff_count = g:CommandLineClockBackoffMultiplier
      return
    endif
  endif
  " For the timer events immediately following new s:last_message,
  " honor the backoff countdown.
  if s:new_message_backoff_count > 0
    let s:new_message_backoff_count -= 1
    return
  endif

  " +++

  let l:clock_day = strftime('%Y-%m-%d')
  let l:clock_hours = strftime('%H:%M')
  let l:clock_datetime = printf('%s %s', l:clock_day, l:clock_hours)

  " +++

  " MAYBE/2021-02-01: Make optional: right-alignment and padding from edge.
  " - Currently, right-aligned with no padding.
  "     let l:cols = &columns - 1
  " - Scratch that, right-aligned with 1 character padding.
  let l:cols = &columns - 2

  " The %{width}S right-aligns a string in the indicated width.
  exec "echo printf('%" . l:cols . "S', '" . l:clock_datetime . "')"

  " +++

endfunction

call s:StartTheClock()

" +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ "

