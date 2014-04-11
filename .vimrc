set shell=/bin/bash
set path=.,,**

" Use Vim settings, rather then Vi settings (much better!).
set nocompatible


" ************************************************************************
" P A C K A G E S
"

filetype off                   " required!

set rtp+=~/.vim/bundle/vundle/
call vundle#rc()

" let Vundle manage Vundle
" required! 
Bundle 'gmarik/vundle'
Bundle 'jamesinchina/eclim-vundle'
Bundle 'L9'
Bundle 'FuzzyFinder'
Bundle 'git://github.com/nathanaelkane/vim-indent-guides.git'
Bundle 'vim-scripts/VimClojure'
Bundle 'davidhalter/jedi-vim'
Bundle 'ervandew/supertab'
Bundle 'Rip-Rip/clang_complete'
Bundle 'eraserhd/vim-ios'
Bundle 'msanders/cocoa.vim'
Bundle 'othree/vim-autocomplpop'
Bundle 'scrooloose/syntastic'
Bundle 'vim-scripts/dbext.vim'
Bundle 'vim-scripts/Vim-R-plugin'
Bundle 'christoomey/vim-tmux-navigator'
Bundle 'vimoutliner/vimoutliner'
Bundle 'altercation/vim-colors-solarized'

filetype plugin indent on     " required!

" ************************************************************************
set nu

" Turn on the verboseness to see everything vim is doing.
"set verbose=9

" allow backspacing over everything in insert mode
set backspace=indent,eol,start

" Indendation, colorscheme, etc

set t_Co=256

" color scheme 
colorscheme elflord
set background=dark

hi IndentGuidesOdd  ctermbg=237
hi IndentGuidesEven ctermbg=234

" do not keep a backup files 
" set nobackup
" set nowritebackup

" use the mouse whenever, wherever
set mouse=a

if has('gui_running')
    " i like about 80 character width lines
    set textwidth=78
    " Set 52 lines for the display
    set lines=52
    " 2 for the status line.
    set cmdheight=2
    " add columns for the Project plugin
    set columns=110
    " enable use of mouse
    set mouse=a
    " for the TOhtml command
    let html_use_css=1
endif

" keep 100 lines of command line history, cause why not?
set history=100  

" show the cursor position all the time
set ruler       

" show (partial) commands
set showcmd     

" do incremental searches (annoying but handy);
set incsearch 

" Show  tab characters. Visual Whitespace.
set list
set listchars=tab:>.

" Set ignorecase on
set ignorecase

" smart search (override 'ic' when pattern has uppers)
set scs

" Set 'g' substitute flag on
" set gdefault

" Set status line
set statusline=[%02n]\ %f\ %(\[%M%R%H]%)%=\ %4l,%02c%2V\ %P%*

" Always display a status line at the bottom of the window
set laststatus=2

" Set vim to use 'short messages'.
" set shortmess=a

" showmatch: Show the matching bracket for the last ')'?
set showmatch

" allow tilde (~) to act as an operator -- ~w, etc.
set notildeop

" Commands for :Explore
let g:explVertical=1    " open vertical split winow
let g:explSplitRight=1  " Put new window to the right of the explorer
let g:explStartRight=0  " new windows go to right of explorer window


if has("gui")
    " set the gui options to:
    "   g: grey inactive menu items
    "   m: display menu bar
    "   r: display scrollbar on right side of window
    "   b: display scrollbar at bottom of window
    "   t: enable tearoff menus on Win32
    "   T: enable toolbar on Win32
    set go=gmr
    set guifont=Courier
endif

set scrolloff=5

" Switch syntax highlighting on, when the terminal has colors
" Also switch on highlighting the last used search pattern.
if &t_Co > 2 || has("gui_running")
    syntax on
    set hlsearch
endif



" ************************************************************************
" C O M M A N D S
"

"switch to directory of current file
command! CD cd %:p:h

" ************************************************************************
" K E Y   M A P P I N G S
"
map <Leader>e :Explore<cr>
map <Leader>s :Sexplore<cr> 


" ************************************************************************
" CouchDan keybindings
" ************************************************************************
"pane movement
noremap <c-h> <c-w>h
noremap <c-j> <c-w>j
noremap <c-k> <c-w>k
noremap <c-l> <c-w>l

"tab movement
map <c-n> gt
map <c-p> gT
nmap <Enter> o<Esc>



" pressing < or > will let you indent/unident selected lines
vnoremap < <gv
vnoremap > >gv

" Don't use Ex mode, use Q for formatting
map Q gq

" Make p in Visual mode replace the selected text with the "" register.
vnoremap p <Esc>:let current_reg = @"<CR>gvs<C-R>=current_reg<CR><Esc>

" Make tab in v mode work like I think it should (keep highlighting):
vmap <tab> >gv
vmap <s-tab> <gv

" map ,L mz1G/Last modified:/e<Cr>CYDATETIME<Esc>`z
map ,L    :let @z=TimeStamp()<Cr>"zpa
map ,datetime :let @z=strftime("%d %b %Y %X")<Cr>"zpa
map ,date :let @z=strftime("%d %b %Y")<Cr>"zpa


func! YankPage()
	let linenumber = line(".")
	normal ggyG
	exec ":"linenumber
endfunc
nmap yp :call YankPage() <Enter>
map <c-a> ggVG

func! NoCodeMode()
	setlocal noexpandtab
	setlocal paste
	setlocal noautoindent
endfu

func! WordProcessorMode() 
  setlocal formatoptions=1 
  setlocal noexpandtab 
  map j gj 
  map k gk
  setlocal spell spelllang=en_us 
  set thesaurus+=/Users/mjr/.vim/thesaurus/mthesaur.txt
  set complete+=s
  set formatprg=par
  setlocal wrap 
  setlocal linebreak 
endfu 
com! WP call WordProcessorMode()

func! CodeMode()
	setlocal tabstop=4
	setlocal shiftwidth=4
	setlocal softtabstop=4
	setlocal expandtab
	setlocal autoindent
	setlocal foldmethod=indent
	setlocal nopaste
endfu
call CodeMode()

" ************************************************************************
" B E G I N  A U T O C O M M A N D S
"
if has("autocmd")

    " Enable file type detection.
    " Use the default filetype settings, so that mail gets 'tw' set to 72,
    " 'cindent' is on in C files, etc.
    " Also load indent files, to automatically do language-dependent indenting.
    filetype plugin indent on

    " When editing a file, always jump to the last known cursor position.
    " Don't do it when the position is invalid or when inside an event handler
    " (happens when dropping a file on gvim).
    autocmd BufReadPost *
      \ if line("'\"") > 0 && line("'\"") <= line("$") |
      \   exe "normal g`\"" |
        \ endif

    " Normally don't automatically format 'text' as it is typed, only do this
    " with comments, at 79 characters.
    autocmd BufNewFile,BufEnter *.c,*.h,*.java,*.jsp set formatoptions-=t tw=79
    autocmd BufNewFile,BufRead *.json set ft=javascript
    "autocmd BufNewFile,BufRead *.txt,*.xls,*.csv,*.tsv call NoCodeMode()
    
    set showmatch 
    map <F5> <Esc>:!clj '%:p'<CR>


    " add an autocommand to update an existing time stamp when writing the file 
    " It uses the functions above to replace the time stamp and restores cursor 
    " position afterwards (this is from the FAQ) 
    autocmd BufWritePre,FileWritePre *   ks|call UpdateTimeStamp()|'s

endif " has("autocmd")

" GUI ONLY type stuff.
if has("gui")
:menu &MyVim.Current\ File.Convert\ Format.To\ Dos :set fileformat=dos<cr> :w<cr>
:menu &MyVim.Current\ File.Convert\ Format.To\ Unix :set fileformat=unix<cr> :w<cr>
:menu &MyVim.Current\ File.Remove\ Trailing\ Spaces\ and\ Tabs :%s/[	]*$//g<cr>
:menu &MyVim.Current\ File.Remove\ Ctrl-M :%s/^M//g<cr>
:menu &MyVim.Current\ File.Remove\ All\ Tabs :retab<cr>
:menu &MyVim.Current\ File.To\ HTML :runtime! syntax/2html.vim<cr>
" these don't work for some reason
":amenu &MyVim.Insert.Date<Tab>,date <Esc><Esc>:,date<Cr>
":amenu &MyVim.Insert.Date\ &Time<Tab>,datetime <Esc><Esc>:let @z=YDATETIME<Cr>"zpa
:amenu &MyVim.Insert.Last\ &Modified<Tab>,L <Esc><Esc>:let @z=TimeStamp()<CR>"zpa
:amenu &MyVim.-SEP1- <nul>
:amenu &MyVim.&Global\ Settings.Toggle\ Display\ Unprintables<Tab>:set\ list!	:set list!<CR>
:amenu &MyVim.-SEP2- <nul>
:amenu &MyVim.&Project :Project<CR>

" hide the mouse when characters are typed
set mousehide
endif

" ************************************************************************
" A B B R E V I A T I O N S 
"
abbr #b /************************************************************************
abbr #e  ************************************************************************/

abbr hosts C:\WINNT\system32\drivers\etc\hosts

" abbreviation to manually enter a timestamp. Just type YTS in insert mode 
iab YTS <C-R>=TimeStamp()<CR>

" Date/Time stamps
" %a - Day of the week
" %b - Month
" %d - Day of the month
" %Y - Year
" %H - Hour
" %M - Minute
" %S - Seconds
" %Z - Time Zone
iab YDATETIME <c-r>=strftime(": %a %b %d, %Y %H:%M:%S %Z")<cr>


" ************************************************************************
"  F U N C T I O N S
"

" copy paste
" set paste
set clipboard=unnamed

"vnoremap <silent> <leader>y :call Putclip(visualmode(), 1)<CR>
"nnoremap <silent> <leader>y :call Putclip('n', 1)<CR>


" first add a function that returns a time stamp in the desired format 
if !exists("*TimeStamp")
    fun TimeStamp()
        return "Last-modified: " . strftime("%d %b %Y %X")
    endfun
endif

" searches the first ten lines for the timestamp and updates using the
" TimeStamp function
if !exists("*UpdateTimeStamp")
    function! UpdateTimeStamp() 
        " Do the updation only if the current buffer is modified 
        if &modified == 1 
            " go to the first line
            exec "1" 
            " Search for Last modified: 
            let modified_line_no = search("Last-modified:") 
            if modified_line_no != 0 && modified_line_no < 10 
                " There is a match in first 10 lines 
                " Go to the : in modified: 
                exe "s/Last-modified: .*/" . TimeStamp()
            endif
        endif
    endfunction
endif

" PostgreSQL
let g:dbext_default_profile_pgsql_local = 'type=PGSQL:user=mjr:passwd=:dbname=analysis'
let g:dbext_default_profile_pgsql_dwh = 'type=PGSQL:user=bbuser_dwh:passwd=bbuser_dwh:dbname=bbdwh:host=10.240.0.231:port=5434'
let g:dbext_default_profile_pgsql_dwh_stg = 'type=PGSQL:user=bbuser_dwh:passwd=bbuser_dwh:dbname=bbdwh:host=10.240.0.230:port=5444'
let g:dbext_default_profile_pgsql_bbcur = 'type=PGSQL:user=bbuser_cur:passwd=bbuser_cur:dbname=bbcur:host=10.240.0.230:port=5433'
let g:dbext_default_profile_pgsql_bbmerchant = 'type=PGSQL:user=bbuser_merchant:passwd=bbuser_merchant:dbname=bbmerchant:host=10.240.0.230:port=5433'
let g:dbext_default_buffer_lines = 20
let g:dbext_default_use_sep_result_buffer = 1 

"Obj C and iOS dev
let g:clang_library_path = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib'
let g:clang_hl_errors = 1
let g:clang_auto_select = 1
inoremap <C-;> <c-x><c-u>


map <leader>f :CommandTFlush<CR>\|:CommandT<CR>
map <leader>xt :call RunKiwiSpecs()<CR>

func! RunKiwiSpecs()
    call RunBuildCommand("xcodebuild -target VimxCodeSpecs -arch x86_64 -configuration Debug")
endfunc

func! RunBuildCommand(cmd)
    echo "Building..."
    exec "silent !" . a:cmd . " >build/vim.log 2>&1"
    silent !grep -q '^\*\* BUILD FAILED' build/vim.log
    redraw!
    if !v:shell_error
        set errorformat=
            \%f:%l:%c:{%*[^}]}:\ error:\ %m,
            \%f:%l:%c:{%*[^}]}:\ fatal error:\ %m,
            \%f:%l:%c:{%*[^}]}:\ warning:\ %m,
            \%f:%l:%c:\ error:\ %m,
            \%f:%l:%c:\ fatal error:\ %m,
            \%f:%l:%c:\ warning:\ %m,
            \%f:%l:\ error:\ %m,
            \%f:%l:\ fatal error:\ %m,
            \%f:%l:\ warning:\ %m
        cfile! build/vim.log
    else
        echo "Building... Ok"
    endif
endfunc 


" Lines added by the Vim-R-plugin command :RpluginConfig (2014-Jan-31 18:07):
filetype plugin on
" Change the <LocalLeader> key:
let maplocalleader = ";"
" Press the space bar to send lines (in Normal mode) and selections to R:
vmap <Space> <Plug>RDSendSelection
nmap <Space> <Plug>RDSendLine
