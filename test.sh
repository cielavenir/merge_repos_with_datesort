#!/bin/bash
export FILTER_BRANCH_SQUELCH_WARNING=1

set -e
# apt-get needs to success
if ! which sponge >/dev/null; then
    echo 'need to install `sponge` to sort commits in-place, which is in `moreutils` package.'
    sudo apt-get -y install moreutils
fi
set +e

function commit () {
### headtime should be unix-int ###
local hashes=$(git -C "${dirroot}" log --pretty=format:%H "${sub}"/master)
# * 処理開始時点でのコミット時刻以前のコミットを取得する *
#local hashsynced=$(git -C "${dirroot}" log --pretty=format:%H --before="$headtime" ${sub}/master | head -1)
local hashsynced=$(git -C "${dirroot}" log --pretty='format:%at %H' "${sub}"/master | awk '$1<='${headtime} | head -1 | cut '-d ' -f2)
# * hashsynced以前のコミット一覧を取得する *
local hashesalready=""
if [ -n "${hashsynced}" ]; then
    local hashesalready=$(git -C "${dirroot}" log --pretty=format:%H "${hashsynced}")
fi
local nhashes=$(<<<"${hashes}" sed '/^$/d'|wc -l)
local nhashesalready=$(<<<"${hashesalready}" sed '/^$/d'|wc -l)
local nhashesnew=$((${nhashes}-${nhashesalready}))
local hashesnew=$(<<<"${hashes}" sed '/^$/d'|head -n ${nhashesnew})

if [ "$nhashesnew" -eq 0 ]; then
    echo '[.] nothing new to import.'
    return
fi

# * 新たに結合するハッシュの最新 *
local hashesnewhead=$(<<<"${hashesnew}" head -n 1)
# * 新たに結合するハッシュの最古 *
local hashesnewtail=$(<<<"${hashesnew}" tail -n 1)

if [ "$nhashesalready" -eq 0 ]; then
    echo '[.] initial import.'
    git -C "${dirroot}" checkout __tmp/master
    git -C "${dirroot}" checkout -b tmpmaster
    # * 強制的にコミットを採用したいので、--allow-empty --allow-empty-message --keep-redundant-commitsとする *
    git -C "${dirroot}" cherry-pick --allow-empty --allow-empty-message --keep-redundant-commits "${hashesnewtail}"
    if [ "${nhashesnew}" -ge 2 ]; then
        # * cherry-pickでA..Bと指定すると、「Aの直後からBまで」を順番にcherry-pickする意味になる *
        # * A^..Bとすれば「Aを含めてBまで」とできるが、Aがroot commitの場合は不可 *
        git -C "${dirroot}" cherry-pick --allow-empty --allow-empty-message --keep-redundant-commits "${hashesnewtail}..${hashesnewhead}"
    fi
    # * ファイルをサブディレクトリに移動するが、committer dataはauthor dataとする *
    ### this env-filter quote must be single. ###
    git -C "${dirroot}" filter-branch -f --tree-filter "mkdir '${sub}' && git mv -k * .gitignore '${sub}'/" --env-filter '
export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
' __tmp/master..tmpmaster
    git -C "${dirroot}" checkout master
    # * リポジトリが再生成された場合でも、--strategy-option=theirsとすればcherry-pickできる *
    git -C "${dirroot}" cherry-pick --strategy-option=theirs --allow-empty --allow-empty-message --keep-redundant-commits __tmp/master..tmpmaster
    git -C "${dirroot}" branch -D tmpmaster
else
    echo '[.] cascading import.'
    git -C "${dirroot}" checkout "${sub}"/master
    git -C "${dirroot}" checkout -b tmpmaster
    # * ファイルをサブディレクトリに移動するが、committer dataはauthor dataとする *
    # * hashesnewtailを含めて、hashesnewtailから先頭までをcherry-pickする *
    ### this quote must be single. ###
    git -C "${dirroot}" filter-branch -f --tree-filter "mkdir '${sub}' && git mv -k * .gitignore '${sub}'/" --env-filter '
export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
' ${hashesnewtail}^..tmpmaster
    git -C "${dirroot}" checkout master
    git -C "${dirroot}" cherry-pick --strategy-option=theirs --allow-empty --allow-empty-message --keep-redundant-commits ${hashesnewtail}^..tmpmaster
    git -C "${dirroot}" branch -D tmpmaster
fi
}

function sortByAuthorDate () {
# * git rebaseで表示される内容をauthor date(int)とする *
git -C "${dirroot}" config rebase.instructionFormat '%at %H'
# * rebase -iのエディタはGIT_SEQUENCE_EDITORで指定できる。 *
# * 第一引数で示されるテキストファイルを編集し再保存するという仕様である。 *
# * これはsort -n -k3とspongeコマンドで実現できる。 *
# * 結合前のheadより後に対し処理を行うようにする。 *
GIT_SEQUENCE_EDITOR='sort -n -k3 $1|sponge $1' git -C "${dirroot}" rebase -i ${head}
# * 結合前のheadより後が日付順に並び替えられたが、commiter dataが書き換わってしまったため、author dataで再度上書きする。 *
git -C "${dirroot}" filter-branch -f --env-filter '
export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
' ${head}..master
}

### fixture
# * headを設定したいので、root commitを古い日付で作成する *
dirroot="dirroot"
if [ ! -d "${dirroot}" ]; then
    mkdir "${dirroot}"
    git -C "${dirroot}" init
    touch "${dirroot}"/.root
    git -C "${dirroot}" add .root
    GIT_COMMITTER_DATE='2000-01-01 00:00:00' git -C "${dirroot}" commit --date='2000-01-01 00:00:00' -m 'root initial'
fi

mkdir dirsub1
git -C dirsub1 init
touch dirsub1/readme.txt
git -C dirsub1 add readme.txt
git -C dirsub1 commit --date='2003-01-01 00:00:00' -m 'sub1 initial'
touch dirsub1/readme2.txt
git -C dirsub1 add readme2.txt
git -C dirsub1 commit --date='2003-01-02 00:00:00' -m 'sub1 add 2'

mkdir dirsub2
git -C dirsub2 init
touch dirsub2/readme.txt
git -C dirsub2 add readme.txt
git -C dirsub2 commit --date='2002-01-01 00:00:00' -m 'sub2 initial'
touch dirsub2/readme2.txt
git -C dirsub2 add readme2.txt
git -C dirsub2 commit --date='2002-06-01 00:00:00' -m 'sub2 add 2'

### case1: creating
# * サブリポジトリを直接編集することはできないので、一旦メインリポジトリの勝手ブランチにcherry-pickする。その土台(__tmp/master)は、適当な古い日付のリポジトリを作成し、それをremote addすることで得られる。 *
if ! git -C "${dirroot}" remote show | grep __tmp > /dev/null; then
    ### need __tmp root to craft some commits.
    mkdir dirtmp
    git -C dirtmp init
    touch dirtmp/.tmp
    git -C dirtmp add .tmp
    GIT_COMMITTER_DATE='2000-01-01 00:00:00' git -C dirtmp commit --date='2000-01-01 00:00:00' -m 'tmp initial'
    git -C "${dirroot}" remote add __tmp ../dirtmp || true
    git -C "${dirroot}" fetch __tmp
    rm -rf dirtmp
fi

git -C "${dirroot}" remote add sub1 ../dirsub1 || true
git -C "${dirroot}" remote add sub2 ../dirsub2 || true
git -C "${dirroot}" fetch sub1
git -C "${dirroot}" fetch sub2

head=$(git -C "${dirroot}" rev-parse master)
headtime=$(git -C "${dirroot}" log --pretty=format:%ct ${head}|head -1|cut '-d ' -f1,2)
sub="sub1"
commit
sub="sub2"
commit
sortByAuthorDate

### fixture2
echo hello > dirsub1/readme.txt
git -C dirsub1 add readme.txt
git -C dirsub1 commit --date='2005-01-01 00:00:00' -m 'edit sub1'
echo world > dirsub2/readme.txt
git -C dirsub2 add readme.txt
git -C dirsub2 commit --date='2004-01-01 00:00:00' -m 'edit sub2'

### case2: adding
git -C "${dirroot}" remote add sub1 ../dirsub1 || true
git -C "${dirroot}" remote add sub2 ../dirsub2 || true
git -C "${dirroot}" fetch sub1
git -C "${dirroot}" fetch sub2

head=$(git -C "${dirroot}" rev-parse master)
headtime=$(git -C "${dirroot}" log --pretty=format:%ct ${head}|head -1|cut '-d ' -f1,2)
sub="sub1"
commit
sub="sub2"
commit
sortByAuthorDate

### fixture3
rm -rf dirsub1
mkdir dirsub1
git -C dirsub1 init
touch dirsub1/readme.txt
echo helloworld > dirsub1/readme.txt
git -C dirsub1 add readme.txt
git -C dirsub1 commit --date='2006-01-01 00:00:00' -m 'reinit'

### case3: reinit
git -C "${dirroot}" remote add sub1 ../dirsub1 || true
git -C "${dirroot}" remote add sub2 ../dirsub2 || true
git -C "${dirroot}" fetch sub1
git -C "${dirroot}" fetch sub2

head=$(git -C "${dirroot}" rev-parse master)
headtime=$(git -C "${dirroot}" log --pretty=format:%ct ${head}|head -1|cut '-d ' -f1,2)
sub="sub1"
commit
sortByAuthorDate
