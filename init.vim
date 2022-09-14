set shell=/bin/bash
set path=.,,** " when searching the path, look in . (current directory) and ** (every direcory recursively starting at current)

" ************************************************************************
" P A C K A G E S
"
call plug#begin()
" sidebar filesystem navigation
    " \n to open/close, navigate to it like a normal pane
    " Plug 'preservim/nerdtree'
    " Plug 'Xuyuanp/nerdtree-git-plugin'
    Plug 'lambdalisue/fern.vim'
    Plug 'gcmt/taboo.vim'
    Plug 'tpope/vim-vinegar'

"Plug 'chrisbra/Recover.vim' " swap file diffing


" tmux integration
" makes ctrl-hjkl move between both vim and tmux panes
    Plug 'christoomey/vim-tmux-navigator'

" commenting: \cs for comment, \cu for uncomment
    Plug 'scrooloose/nerdcommenter'

" :UT to open a tree of undo paths for the current pane.
    Plug 'mbbill/undotree'

" vim buffers are more like tabs
    Plug 'ap/vim-buftabline'
    " automatically enter/exit paste on inhuman input speed
    " added because paste disables abbreviations
    Plug 'roxma/vim-paste-easy'

" for fuzzyfinding files/contents
    " automatically binds to ctrl-p, rebound to ctrl-s later
    Plug 'kien/ctrlp.vim'
    Plug 'mileszs/ack.vim'
    Plug 'henrik/vim-qargs'

" tab completion everywhere, code completion
    Plug 'ervandew/supertab'
    "Plug 'Valloric/YouCompleteMe'
    "Plug 'Shougo/neocomplete.vim'

" Linting (error checking) and syntax highlighting
    "Plug 'scrooloose/syntastic'
    "Plug 'dart-lang/dart-vim-plugin'
    Plug 'altercation/vim-colors-solarized'
    "Plug 'plasticboy/vim-markdown'
    "Plug 'lepture/vim-jinja'
    "Plug 'othree/html5.vim'
    "Plug 'JulesWang/css.vim'
    "Plug 'genoma/vim-less'
    "Plug 'cakebaker/scss-syntax.vim'
    Plug 'kien/rainbow_parentheses.vim'
    "Plug 'hdima/python-syntax'
    "Plug 'meatballs/vim-xonsh'
    "Plug 'cespare/vim-toml'

    "Plug 'jparise/vim-graphql'

    "Plug 'shime/vim-livedown'
    Plug 'tmux-plugins/vim-tmux'
    "Plug 'reedes/vim-pencil'
    "Plug 'reedes/vim-wordy'
    "Plug 'reedes/vim-lexical'
    "Plug 'reedes/vim-litecorrect'
    "Plug 'reedes/vim-textobj-quote'
    "Plug 'reedes/vim-textobj-sentence'
    "Plug 'kana/vim-textobj-user' "dependency
    "Plug 'junegunn/limelight.vim'

    "Plug 'vimwiki/vimwiki'



" Linting (error checking) and syntax highlighting
    "Plug 'godlygeek/tabular'
    " :Tab /= on the next line would do:
    " a = 'foo';   => a       = 'foo';
    " bortlty = 1; => bortlty = 1;

" Clojure
   "Plug 'guns/vim-clojure-static'
   "Plug 'tpope/vim-fireplace'
   "Plug 'vim-scripts/paredit.vim'

" Git plugin for vim
    Plug 'tpope/vim-fugitive'


" js / ts / flow
    "Plug 'Shougo/vimproc.vim'
    "Plug 'leafgarland/typescript-vim'
    "Plug 'Quramy/vim-js-pretty-template'
    "Plug 'ruanyl/vim-fixmyjs'

"Plug 'w0rp/ale'
    "Plug 'Quramy/tsuquyomi'
    "Plug 'peitalin/vim-jsx-typescript'
    "Plug 'flowtype/vim-flow'


" js, jsx, and json highlighting / linting:
    "Plug 'pangloss/vim-javascript'
    "Plug 'gkz/vim-ls'
    "Plug 'isRuslan/vim-es6'
    "Plug 'elzr/vim-json'
    "Plug 'vito-c/jq.vim'
    "Plug 'mxw/vim-jsx'

"Plug 'roxma/vim-hug-neovim-rpc'
"Plug 'roxma/nvim-yarp'
"Plug 'autozimu/LanguageClient-neovim'
"
"Plug 'reasonml-editor/vim-reason-plus'

Plug 'editorconfig/editorconfig-vim'

call plug#end()

" store swap files here
set directory^=$HOME/.vim/tmp//


" ************************************************************************
" making the interface friendly. Mouse always on, numbered lines, etc
"
  set backspace=indent,eol,start " allow backspacing over everything in insert mode
  set scrolloff=5
  set nu               "numbered lines
  set ruler            "show cursor
  "set showcmd          "partial commands
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
  set clipboard+=unnamedplus
  set foldmethod=indent

"set virtualedit=all
syntax on

" Indendation, colorscheme, etc
    set t_Co=256
    colorscheme solarized "altercation/vim-colors-solarized
    set background=dark
    "visible whitespace
    set list
    set listchars=tab:>.
    set nolist wrap linebreak breakat&vim    


" https://github.com/preservim/nerdtree/blob/14af89743ac1c31ff9bb43682025eda50333a7d5/lib/nerdtree/opener.vim#L53-L68
" sdfsfsdf
"
" Returns the first window ID containing a file buffer
"
" Iterates through window numbers until the last (winnr('$')),
" Skipping special buffer types & preview windows
function! FirstFileWindowID()
    let i = 1
    while i <= winnr('$')
        let bnum = winbufnr(i)
        if bnum !=# -1 && getbufvar(bnum, '&buftype') ==# ''
                    \ && !getwinvar(i, '&previewwindow')
            " TODO I don't know what excluding &hidden does in the original,
            " but may be desirable for correctness
            return win_getid(i)
        endif
        let i += 1
    endwhile
    return -1
endfunction

"tab movement (ctrl-n for next tab, ctrl-p for previous)
map <c-n> :call win_execute(FirstFileWindowID(), 'bnext')<CR>
map <c-p> :call win_execute(FirstFileWindowID(), 'bprev')<CR>


" Close window when quitting last buffer
autocmd BufDelete * if len(filter(range(1, bufnr('$')), 'empty(bufname(v:val)) && buflisted(v:val)')) == 1 | quit | endif

" tab-like :q behavior for buffers
" Prevent accidental closing of all buffers when doing :wq or :q
cnoreabbrev wq w<bar>bdelete
cnoreabbrev q bdelete
cnoreabbrev Q quit


" added because paste disables abbreviations,
" breaking the above
set nopaste

"enter in normal mode to insert in new line
    nmap <Enter> o<Esc>

" good config for programming
func! CodeMode()
	set tabstop=2
	set shiftwidth=2
	set softtabstop=2
	set expandtab
	set autoindent
	set foldmethod=indent
endfu

call CodeMode()

func! AccountingMode()
    set tabstop=13
    set list
    set listchars=tab:>.
    set softtabstop=0
endfu


func! ProseMode()
  set spellsuggest=15
  highlight LineNr ctermfg=0 ctermbg=8

  " http://www.terminally-incoherent.com/blog/2013/06/17/using-vim-for-writing-prose/
  " see :help fo-table
  setlocal formatoptions=ant
  " setlocal textwidth=80

  setlocal wrapmargin=0

  #call pencil#init({'wrap': 'hard', 'autoformat': 0})
  call pencil#init({'wrap': 'soft', 'autoformat': 0})
  call lexical#init()
  call textobj#sentence#init()
  call litecorrect#init()
  "call textobj#quote#init()
    "call LimeLight()
endfu

" augroup pencil
"   autocmd!
"   autocmd FileType markdown,mkd,text call ProseMode()
" augroup END

let g:word_count="<unknown>"
set updatetime=1000
augroup WordCounter
  au!  CursorHold,CursorHoldI * call UpdateWordCount()
augroup END

function WordCount()
  return g:word_count + " words"
endfunction

function UpdateWordCount()
 let lnum = 1
 let n = 0
 while lnum <= line('$')
   let n = n + len(split(getline(lnum)))
   let lnum = lnum + 1
 endwhile
 let g:word_count = n
endfunction


" prosemode
" Color name (:help cterm-colors) or ANSI code
" let g:limelight_conceal_ctermfg = 241  " Solarized Base1


" Set status line
set statusline=[%02n]\ %f\ %{fugitive#statusline()}\ %{WordCount()}\ %(\[%M%R%H]%)%=\ %4l,%02c%2V\ %P%*


let g:vimwiki_list = [{
      \ 'path': '~/code/personal/micimize.com/library',
      \ 'syntax': 'markdown',
      \ 'ext': '.md'
      \ }]

let g:vimwiki_markdown_link_ext = 1
let g:vimwiki_auto_header = 1
    


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

func! YankPage()
	let linenumber = line(".")
	normal ggyG
	exec ":"linenumber
endfunc
nmap yp :call YankPage() <Enter>
map <c-a> ggVG 
"ctrl-shift-a is ignored in iterm to make way for obs keybindings

let g:ctrlp_user_command = ['.git/', 'git --git-dir=%s/.git ls-files -oc --exclude-standard']

" it would be interesting to look into purely using tmux panes
" and some other cli util for file navigation
" https://vi.stackexchange.com/questions/317/can-i-open-a-file-in-an-existing-vim-instance-from-an-external-command
" let g:netrw_banner = 0
" let g:netrw_liststyle = 3
" let g:netrw_browse_split = 4
" let g:netrw_altv = 1
" let g:netrw_winsize = 25
" map <Leader>n :Lexplore<CR>
" 
" let g:netrw_list_hide= '.*\.swp$,.*\.swo$,.*\.swm$,.*\.pyc$'


" augroup netrw_mapping
"   autocmd!
"   autocmd filetype netrw call NetrwMapping()
" augroup END
" 
" function! NetrwMapping()
"   nnoremap <buffer> <c-l> :wincmd l<cr>
" endfunction
 

" change o to t as regular opening is now
" like open-in-tab behavior
" let NERDTreeMapOpenInTab='\t'
" let NERDTreeMapActivateNode='t'

" map <Leader>n :NERDTreeToggle<CR>
" let NERDTreeAutoDeleteBuffer = 1
" let g:NERDTreeGitStatusIndicatorMapCustom = {
"     \ "Modified"  : "_",
"     \ "Staged"    : "S",
"     \ "Untracked" : "U",
"     \ "Renamed"   : ">",
"     \ "Unmerged"  : "%",
"     \ "Deleted"   : "D",
"     \ "Dirty"     : "%",
"     \ "Clean"     : "C",
"     \ "Unknown"   : "?"
"     \ }
" let NERDTreeIgnore = ['\.pyc$']
map <Leader>n :Fern . -drawer -toggle<CR>

function! s:init_fern() abort
  nmap <buffer> o <Plug>(fern-action-open)
  setlocal nonumber
endfunction

augroup fern-custom
  autocmd! *
  autocmd FileType fern call s:init_fern()
augroup END

com! UT UndotreeToggle


let g:syntastic_mode_map = { 'mode': 'active',
                           \ 'active_filetypes': ['ruby', 'php', 'javascript', 'jsx', 'tsx'],
                           \ 'passive_filetypes': ['cpp', 'java', 'js'] }
                           
"let g:syntastic_typescript_tsc_args = '--experimentalDecorators true'
"let g:syntastic_javascript_checkers = ['eslint']
"let g:syntastic_typescript_checkers = ['tslint']
"let g:jsx_ext_required = 0

let g:syntastic_python_checkers=['flake8', 'python3']

com! S call SyntasticCheck()

set hidden
let g:LanguageClient_serverCommands = {
    \ 'reason': ['ocaml-language-server', '--stdio'],
    \ 'ocaml': ['ocaml-language-server', '--stdio'],
    \ }

let g:LanguageClient_autoStart = 1

nnoremap <silent> K :call LanguageClient_textDocument_hover()<CR>
nnoremap <silent> gd :call LanguageClient_textDocument_definition()<CR>

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
    "autocmd BufNewFile,BufEnter *.c,*.h,*.java,*.jsp set formatoptions-=t tw=79
    autocmd BufNewFile,BufEnter *.html,*.htm,*.shtml,*.stm set ft=jinja
    
    set showmatch 
    map <F5> <Esc>:!clj '%:p'<CR>

    autocmd FileType javascript,json,typescript setlocal shiftwidth=2
    autocmd FileType javascript,json,typescript setlocal tabstop=2
    autocmd FileType javascript,json,typescript setlocal softtabstop=2

    autocmd FileType python setlocal shiftwidth=4
    autocmd FileType python setlocal tabstop=4
    autocmd FileType python setlocal softtabstop=4

    autocmd FileType typescript let g:fixmyjs_engine = 'tslint'
    autocmd QuickFixCmdPost [^l]* nested cwindow
    autocmd QuickFixCmdPost    l* nested lwindow
    "autocmd BufWritePost *ts make

    func! SyntaxCheckJs ()
        SyntasticCheck()
        Fixmyjs()
    endfunc
    autocmd FileType javascript,json,typescript com! S call SyntasticCheckJs()

    autocmd FileType html noremap <buffer> <c-f> :call HtmlBeautify()<cr>
    "autocmd BufNewFile,BufEnter *.less set ft=css
    "autocmd FileType css noremap <buffer> <c-f> :call CSSBeautify()<cr>

    "autocmd FileType clojure noremap <buffer> <enter> :Eval<cr>
    "autocmd FileType clojurescript noremap <buffer> <enter> :Eval<cr>

endif " has("autocmd")

"let g:jsCommand='node'
"let $JS_CMD='node'

"let g:javascript_plugin_flow = 1

"" neocomplete
let g:neocomplete#enable_at_startup = 1
let g:neocomplete#enable_smart_case = 1
let g:neocomplete#sources#syntax#min_keyword_length = 3

" <TAB>: completion.
inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
autocmd FileType python setlocal omnifunc=pythoncomplete#Complete
autocmd FileType javascript setlocal omnifunc=javascriptcomplete#CompleteJS
autocmd FileType javascript setlocal omnifunc=tern#Complete

"let g:ycm_server_keep_logfiles = 1
"let g:ycm_server_log_level = 'debug'
"let g:ycm_path_to_python_interpreter = '/usr/bin/python'
"let g:tern_show_argument_hints='on_hold'
"let g:tern_map_keys=1
let g:syntastic_javascript_checkers = ['eslint', 'flow']
let g:syntastic_javascript_flow_exe = 'flow'
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1


set diffopt+=vertical
autocmd StdinReadPre * let s:std_in=1

if &t_Co > 2 || has("gui_running")
    syntax on     " Switch syntax highlighting on, when the terminal has colors
    set hlsearch  " Also switch on highlighting the last used search pattern. 
endi

