set shell=/bin/bash
set path=.,,**

" ************************************************************************
" P A C K A G E S
"
filetype off                   " required!
set rtp+=~/.vim/bundle/vundle/
call vundle#rc()
" let Vundle manage Vundle
" required! 

" queued for deletion: 11-15-2014
    "Bundle 'MarcWeber/vim-addon-mw-utils'
    "Bundle 'tomtom/tlib_vim'
    "Bundle 'tpope/vim-rails'
    "Bundle 'git://github.com/nathanaelkane/vim-indent-guides.git'
    "Bundle 'davidhalter/jedi-vim'
    "Bundle 'othree/vim-autocomplpop'
    "Bundle 'FuzzyFinder'
    "Bundle 'othree/xml.vim'
    "Bundle 'sukima/xmledit'
    "Bundle 'Rip-Rip/clang_complete'
    "Bundle 'eraserhd/vim-ios'
    "Bundle 'msanders/cocoa.vim'
    "Bundle 'vim-scripts/Vim-R-plugin'
    "Bundle 'christoomey/vim-tmux-navigator'
    "Bundle 'jiangmiao/auto-pairs'

" never used, but seem useful:
    "Bundle 'mattn/emmet-vim'
    "Bundle 'garbas/vim-snipmate'
    "Bundle 'honza/vim-snippets'
" useful in the past:
    "Bundle 'ivanov/vim-ipython'
    "Bundle 'vimoutliner/vimoutliner'

Bundle 'gmarik/vundle'
Bundle 'L9'

Bundle 'scrooloose/nerdtree'
Bundle 'jistr/vim-nerdtree-tabs'
Bundle 'mbbill/undotree'
Bundle 'scrooloose/nerdcommenter'
Bundle 'kien/ctrlp.vim' 

Bundle 'vim-scripts/dbext.vim'

Bundle 'ervandew/supertab'
Bundle 'scrooloose/syntastic'

Bundle 'altercation/vim-colors-solarized'

Bundle 'godlygeek/tabular'
Bundle 'plasticboy/vim-markdown'

Bundle 'guns/vim-clojure-static'
Bundle 'tpope/vim-fireplace'
Bundle 'vim-scripts/paredit.vim'
Bundle 'kien/rainbow_parentheses.vim'

Bundle 'maksimr/vim-jsbeautify'
Bundle 'Glench/Vim-Jinja2-Syntax'
Bundle 'groenewege/vim-less'

Bundle "pangloss/vim-javascript"
Bundle 'mxw/vim-jsx'
Bundle 'jordwalke/JSXVimHint'
Bundle 'tpope/vim-fugitive'


filetype plugin indent on     " required!
" ************************************************************************
" allow backspacing over everything in insert mode
set backspace=indent,eol,start

" Indendation, colorscheme, etc
    set t_Co=256
    colorscheme solarized
    set background=dark
    hi IndentGuidesOdd  ctermbg=237
    hi IndentGuidesEven ctermbg=234
    "visible whitespace
    set list
    set listchars=tab:>.
    set nolist wrap linebreak breakat&vim    
" Set status line
set statusline=[%02n]\ %f\ %{fugitive#statusline()}\ %(\[%M%R%H]%)%=\ %4l,%02c%2V\ %P%*

set mouse=a " use the mouse whenever, wherever
set foldmethod=indent

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
let g:rbpt_colorpairs = [
    \ ['brown',       'RoyalBlue3'],
    \ ['Darkblue',    'SeaGreen3'],
    \ ['darkgreen',   'firebrick3'],
    \ ['darkcyan',    'RoyalBlue3'],
    \ ['darkred',     'SeaGreen3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['brown',       'firebrick3'],
    \ ['gray',        'RoyalBlue3'],
    \ ['black',       'SeaGreen3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['Darkblue',    'firebrick3'],
    \ ['darkgreen',   'RoyalBlue3'],
    \ ['darkcyan',    'SeaGreen3'],
    \ ['darkred',     'DarkOrchid3'],
    \ ['red',         'firebrick3'],
    \ ]

let g:rbpt_max = 15
let g:rbpt_loadcmd_toggle = 0
au VimEnter * RainbowParenthesesToggle
au Syntax * RainbowParenthesesLoadRound
au Syntax * RainbowParenthesesLoadSquare
au Syntax * RainbowParenthesesLoadBraces

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
syntax on

" Commands for :Explore
let g:explVertical=1    " open vertical split winow
let g:explSplitRight=1  " Put new window to the right of the explorer
let g:explStartRight=0  " new windows go to right of explorer window


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

let g:ctrlp_map = '<c-s>'
"let g:ctrlp_cmd = 'CtrlS'

" ************************************************************************
" CouchDan keybindings
" ************************************************************************
"
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


"map j gj 
"map k gk
"func! WordProcessorMode() 
  "setlocal formatoptions=1 
  "setlocal noexpandtab 
  "setlocal spell spelllang=en_us 
  "set thesaurus+=/Users/mjr/.vim/thesaurus/mthesaur.txt
  "set complete+=s
  "set formatprg=par
  "setlocal wrap 
  "setlocal linebreak 
"endfu 
"com! WP call WordProcessorMode()

"func! NoCodeMode()
	"setlocal noexpandtab
	"setlocal paste
	"setlocal noautoindent
"endfu
"com! NCM call NoCodeMode()
"func! ReportFromTODO()
	"g/	\[_\].*/d
	"%s/^\[.\].*% //g
	"%s/\[X\]/*/g
"endfunc!

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


let g:dbext_default_profile_pgsql_local = 'type=PGSQL:user=mjr:passwd=:dbname=type_flashcards'
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

    autocmd FileType javascript noremap <buffer>  <c-f> :call JsBeautify()<cr>
    autocmd FileType html noremap <buffer> <c-f> :call HtmlBeautify()<cr>
    autocmd FileType css noremap <buffer> <c-f> :call CSSBeautify()<cr>

    autocmd FileType clojure noremap <buffer> <enter> :Eval<cr>
    autocmd FileType clojurescript noremap <buffer> <enter> :Eval<cr>

endif " has("autocmd")
set mousehide
let g:jsCommand='node'
let $JS_CMD='node'
let g:syntastic_javascript_checkers = ['jsxhint']
let g:syntastic_javascript_jsxhint_exec = 'jsx-jshint-wrapper'

" ************************************************************************
" A B B R E V I A T I O N S 
"
"abbr #e  ************************************************************************/
" abbreviation to manually enter a timestamp. Just type YTS in insert mode
iab YTS <C-R>=TimeStamp()<CR>
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
iab YDATETIME <c-r>=strftime(": %a %b %d, %Y %H:%M:%S %Z")<cr>



set clipboard=unnamed

autocmd StdinReadPre * let s:std_in=1
"autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | <Plug>NERDTreeTabsToggle | endif

map <Leader>n <plug>NERDTreeTabsToggle<CR>
com! UT call UndotreeToggle()

" Bulgarian
	noremap я q
	noremap в w
	noremap е e
	noremap р r
	noremap т t
	noremap ъ y
	noremap у u
	noremap и i
	noremap о o
	noremap п p
	noremap а a
	noremap с s
	noremap д d
	noremap ф f
	noremap г g
	noremap х h
	noremap й j
	noremap к k
	noremap л l
	noremap з z
	noremap ь x
	noremap ц c
	noremap ж v
	noremap б b
	noremap н n
	noremap м m
	noremap ч `
	noremap ш [
	noremap щ ]
	noremap ю \
	noremap Я Q
	noremap В W
	noremap Е E
	noremap Р R
	noremap Т T
	noremap Ъ Y
	noremap У U
	noremap И I
	noremap О O
	noremap П P
	noremap А A
	noremap С S
	noremap Д D
	noremap Ф F
	noremap Г G
	noremap Х H
	noremap Й J
	noremap К K
	noremap Л L
	noremap З Z
	noremap Ь X
	noremap Ц C
	noremap Ж V
	noremap Б B
	noremap Н N
	noremap М M
	"noremap Ч ~
	"noremap Ш {
	"noremap Щ }
	"noremap Ю |
"
"
"
