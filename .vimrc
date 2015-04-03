set shell=/bin/bash
set path=.,,** " when searching the path, look in . (current directory) and ** (every direcory recursively starting at current)

" ************************************************************************
" P A C K A G E S
"
filetype off                   " required!
set rtp+=~/.vim/bundle/vundle/
call vundle#rc()
" Vundle is the vim package manager.
" Bundles are usually of the form user/repo (https://github.com/user/repo)
" let Vundle manage Vundle

" required by vundle
Bundle 'gmarik/vundle'
Bundle 'L9'

" sidebar filesystem navigation
    " \n to open/close, navigate to it like a normal pane
    Bundle 'scrooloose/nerdtree'
   " makes nerdtree consistent across tabs
    Bundle 'jistr/vim-nerdtree-tabs'

" commenting: \cs for comment, \cu for uncomment
    Bundle 'scrooloose/nerdcommenter'

" :UT to open a tree of undo paths for the current pane.
    Bundle 'mbbill/undotree'

" for fuzzyfinding files/contents
    " automatically binds to ctrl-p, rebound to ctrl-s later
    Bundle 'kien/ctrlp.vim'

" tab completion everywhere
    Bundle 'ervandew/supertab'

" Linting (error checking) and syntax highlighting
    Bundle 'scrooloose/syntastic'
    Bundle 'altercation/vim-colors-solarized'
    Bundle 'plasticboy/vim-markdown'
    Bundle 'Glench/Vim-Jinja2-Syntax'
    Bundle 'groenewege/vim-less'
    Bundle 'kien/rainbow_parentheses.vim'

" Linting (error checking) and syntax highlighting
    Bundle 'godlygeek/tabular'
    " :Tab /= on the next line would do:
    " a = 'foo';   => a       = 'foo';
    " bortlty = 1; => bortlty = 1;

" Clojure
    Bundle 'guns/vim-clojure-static'
    Bundle 'tpope/vim-fireplace'
    Bundle 'vim-scripts/paredit.vim'


" Git plugin for vim
    Bundle 'tpope/vim-fugitive'

" js, jsx, and json highlighting / linting:
    Bundle "pangloss/vim-javascript"
    Bundle 'elzr/vim-json'
    Bundle 'mxw/vim-jsx'
    Bundle 'jordwalke/JSXVimHint'
    Bundle 'maksimr/vim-jsbeautify' 

" for connecting to a db directly from vim
" Bundle 'vim-scripts/dbext.vim'

"seem useful:
    "Bundle 'mattn/emmet-vim'
    "Bundle 'garbas/vim-snipmate'
    "Bundle 'honza/vim-snippets'

filetype plugin indent on     " required!



" ************************************************************************
" making the interface friendly. Mouse always on, numbered lines, etc
"
set backspace=indent,eol,start " allow backspacing over everything in insert mode
set scrolloff=5
set nu               "numbered lines
set ruler            "show cursor
set showcmd          "partial commands
set incsearch        "incremental search 
set ignorecase
set history=10000
set scs              " smart search (override 'ic' when pattern has uppers)
set laststatus=2     " Always display a status line at the bottom of the window
set showmatch        " showmatch: Show the matching bracket for the last ')'
set notildeop        " allow tilde (~) to act as an operator -- ~w, etc.
set mouse=a " use the mouse whenever, wherever
set mousehide
set clipboard=unnamed
set foldmethod=indent
syntax on

" pane movement
" makes ctrl-hjkl the same as normal mode, just for panes instead of chars
    noremap <c-h> <c-w>h
    noremap <c-j> <c-w>j
    noremap <c-k> <c-w>k
    noremap <c-l> <c-w>l

"tab movement (ctrl-n for next tab, ctrl-p for previous)
    map <c-n> gt
    map <c-p> gT

"enter in normal mode to insert in new line
    nmap <Enter> o<Esc>

" good config for programming
func! CodeMode()
	set tabstop=4
	set shiftwidth=4
	set softtabstop=4
	set expandtab
	set autoindent
	set foldmethod=indent
	set nopaste
endfu
com! CM call CodeMode()
call CodeMode()


" Indendation, colorscheme, etc
    set t_Co=256
    colorscheme solarized "altercation/vim-colors-solarized
    set background=dark
    "visible whitespace
    set list
    set listchars=tab:>.
    set nolist wrap linebreak breakat&vim    
" Set status line
set statusline=[%02n]\ %f\ %{fugitive#statusline()}\ %(\[%M%R%H]%)%=\ %4l,%02c%2V\ %P%*

" kien/rainbow_parentheses.vim - theme that should show up on all backgrounds
let g:rbpt_colorpairs = [
  \ [ '13', '#6c71c4'],
  \ [ '5',  '#d33682'],
  \ [ '1',  '#dc322f'],
  \ [ '9',  '#cb4b16'],
  \ [ '3',  '#b58900'],
  \ [ '2',  '#859900'],
  \ [ '6',  '#2aa198'],
  \ [ '4',  '#268bd2'],
  \ ]
augroup rainbow_parentheses
  au!
  au VimEnter * RainbowParenthesesActivate
  au BufEnter * RainbowParenthesesLoadRound
  au BufEnter * RainbowParenthesesLoadSquare
  au BufEnter * RainbowParenthesesLoadBraces
augroup END


" ************************************************************************
" COMMANDS
"

"switch to directory of current file
    command! CD cd %:p:h

" Commands and mappings for :Explore, searching, etc
    let g:explVertical=1    " open vertical split winow
    let g:explSplitRight=1  " Put new window to the right of the explorer
    let g:explStartRight=0  " new windows go to right of explorer window
    map <Leader>e :Explore<cr>
    map <Leader>s :Sexplore<cr> 

" kien/ctrlp.vim
    let g:ctrlp_map = '<c-s>'

" pressing < or > will let you indent/unident selected lines
    vnoremap < <gv
    vnoremap > >gv

" Don't use Ex mode, use Q for formatting
    map Q gq

" Make tab in v mode work like I think it should (keep highlighting):
    vmap <tab> >gv
    vmap <s-tab> <gv

" Some timestamp stuff
    " map ,L mz1G/Last modified:/e<Cr>CYDATETIME<Esc>`z
    map ,L    :let @z=TimeStamp()<Cr>"zpa
    map ,datetime :let @z=strftime("%d %b %Y %X")<Cr>"zpa
    map ,date :let @z=strftime("%d %b %Y")<Cr>"zpa

    " first add a function that returns a time stamp in the desired format 
    if !exists("*TimeStamp")
        fun TimeStamp()
            return strftime("%d %b %Y %X")
        endfun
    endif


func! YankPage()
	let linenumber = line(".")
	normal ggyG
	exec ":"linenumber
endfunc
nmap yp :call YankPage() <Enter>
map <c-a> ggVG

map <Leader>n <plug>NERDTreeTabsToggle<CR>
com! UT call UndotreeToggle()


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
    
    set showmatch 
    map <F5> <Esc>:!clj '%:p'<CR>

    "maksimr/vim-jsbeautify
        autocmd FileType javascript noremap <buffer>  <c-f> :call JsBeautify()<cr>
        autocmd FileType html noremap <buffer> <c-f> :call HtmlBeautify()<cr>
        autocmd FileType css noremap <buffer> <c-f> :call CSSBeautify()<cr>

        autocmd FileType clojure noremap <buffer> <enter> :Eval<cr>
        autocmd FileType clojurescript noremap <buffer> <enter> :Eval<cr>

endif " has("autocmd")

let g:jsCommand='node'
let $JS_CMD='node'

"jordwalke/JSXVimHint
    let g:syntastic_javascript_checkers = ['jsxhint']
    let g:syntastic_javascript_jsxhint_exec = 'jsx-jshint-wrapper'

" ************************************************************************
" A B B R E V I A T I O N S 
"
"abbr #e  ************************************************************************/
"iab #-># #########################################################################

" Date/Time stamps
    " %a - Day of the week
    " %b - Month
    " %d - Day of the month
    " %Y - Year
    " %H - Hour
    " %M - Minute
    " %S - Seconds
    " %Z - Time Zone
    "
    " abbreviation to manually enter a timestamp. Just type YTS in insert mode
    iab YTS <C-R>=TimeStamp()<CR>
    iab YDATETIME <c-r>=strftime(": %a %b %d, %Y %H:%M:%S %Z")<cr>

set diffopt+=vertical
autocmd StdinReadPre * let s:std_in=1

" In case you don't use a terminal
if has('gui_running')
    set textwidth=78 "78 character width lines
    set lines=52
    set cmdheight=2 " 2 for the status line.
    set columns=110 " add columns for the Project plugin
    set mouse=a " enable use of mouse
    let html_use_css=1 " for the TOhtml command
endif
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
if &t_Co > 2 || has("gui_running")
    syntax on     " Switch syntax highlighting on, when the terminal has colors
    set hlsearch  " Also switch on highlighting the last used search pattern. 
endi
