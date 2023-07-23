#!/bin/bash
set -Eeuo pipefail
set -o nounset
set -o errexit

get_chrome() {
  local product="$1"
  local chrome="8A69D345-D564-463C-AFF1-A69D9E530F96"
  local canary="4EA16AC7-FD5A-47C3-875B-DBF4A2008C20"
  if [[ "$product" == *"stable"* || "$product" == *"chrome"* ]];then
    product=$chrome
  elif [[ "$product" == *"canary"*  ]]; then
    product=$canary
  else
    printf "Error: please select on of products: chrome, canary"
    return
  fi
  local req="<?xml version='1.0' encoding='UTF-8'?>
<request protocol='3.0' version='1.3.23.9' shell_version='1.3.21.103' ismachine='0' sessionid='{3597644B-2952-4F92-AE55-D315F45F80A5}' installsource='ondemandcheckforupdate' requestid='{CD7523AD-A40D-49F4-AEEF-8C114B804658}' dedup='cr'>
    <hw sse='1' sse2='1' sse3='1' ssse3='1' sse41='1' sse42='1' avx='1' physmemory='12582912' />
    <os platform='win' version='6.3' arch='x86' />
    <app appid='{$product}' ap='' version='' nextversion='' lang='' brand='GGLS' client=''>
        <updatecheck />
    </app>
</request>"
  local response="$(curl "https://tools.google.com/service/update2" --data "$req" 2> /dev/null )"
  eval "$(cat <<<$response | xmllint - --xpath '//response/app/updatecheck/urls/url[6]/@codebase' |
    sed 's/codebase/local baseurl/')" > /dev/null 2>&1
  eval "$(cat <<<$response | xmllint - --xpath "//response/app/updatecheck/manifest/actions/action/@run" |
    sed 's/run/local file/')" > /dev/null 2>&1
  eval "$(cat <<<$response | xmllint - --xpath "//response/app/updatecheck/manifest/@version" |
    sed 's/version/local ver/')" > /dev/null 2>&1
  eval "$(cat <<<$response | xmllint - --xpath "//response/app/updatecheck/manifest/packages/package/@hash_sha256" |
    sed 's/hash_sha256/local sum/')" > /dev/null 2>&1
  local url="${baseurl}${file}"
  printf "%s\n" "{\"name\": \"chromeinstaller.exe\",\"ver\": \"$ver\",\"sum\":\"$sum\", \"url\":\"$url\"}"
}

get_chrome_driver(){
  local CHROME_DRIVER_URL="https://chromedriver.storage.googleapis.com"
  local CANARY_BASE_URL="https://www.googleapis.com/download/storage/v1/b/chromium-browser-snapshots/o/Win"
  local product="$1"
  local ver
  local url
  local sum
  if [[ "$product" == *"stable"* || "$product" == *"chrome"* ]];then
    ver=$(curl "$CHROME_DRIVER_URL/LATEST_RELEASE" 2> /dev/null)
    url="$CHROME_DRIVER_URL/$ver/chromedriver_win32.zip"
    sum=$(curl "$url" 2> /dev/null | sha256sum | sed 's/  -//' )
  elif [[ "$product" == *"canary"*  ]]; then
    ver=$(curl "$CANARY_BASE_URL%2FLAST_CHANGE?alt=media" 2> /dev/null)
    url="$CANARY_BASE_URL%2F$ver%2Fchromedriver_win32.zip?alt=media"
    sum=$(curl "$url" 2> /dev/null | sha256sum | sed 's/  -//')
  else
    printf "Error: please select one of products: chrome, canary"
    return
  fi
  printf "%s\n" "{\"name\": \"chromedriver.zip\",\"ver\": \"$ver\",\"sum\":\"$sum\", \"url\":\"$url\"}"
}


echo "https://commondatastorage.googleapis.com/chromium-browser-snapshots/index.html?prefix=Win/"


#from https://github.com/neoFelhz/ChromeChecker/blob/5fa73d9bad4bc6bc295c9247f668bfed45c8e982/checker.sh (The Unlicense)

eval "$(cat <<<$response_canary | xmllint - --xpath '//response/app/updatecheck/urls/url[6]/@codebase' |
  sed s/codebase/local baseurl/)"
eval "$(cat <<<$response_canary | xmllint - --xpath "//response/app/updatecheck/manifest/actions/action/@run" |
  sed s/run/local file/)"
eval "$(cat <<<$response_canary | xmllint - --xpath "//response/app/updatecheck/manifest/packages/package/@hash_sha256" |
  sed s/hash_sha256/local sum/)"

printf "$hash_sha256 ${run}" >"$run.sha256"
url="${codebase}${run}"
curl $url --output $run
sha256sum -c "$run.sha256"




canary="4EA16AC7-FD5A-47C3-875B-DBF4A2008C20"
product=$canary
req="<?xml version='1.0' encoding='UTF-8'?>
<request protocol='3.0' version='1.3.23.9' shell_version='1.3.21.103' ismachine='0' sessionid='{3597644B-2952-4F92-AE55-D315F45F80A5}' installsource='ondemandcheckforupdate' requestid='{CD7523AD-A40D-49F4-AEEF-8C114B804658}' dedup='cr'>
    <hw sse='1' sse2='1' sse3='1' ssse3='1' sse41='1' sse42='1' avx='1' physmemory='12582912' />
    <os platform='win' version='6.3' arch='x86' />
    <app appid='{$product}' ap='' version='' nextversion='' lang='' brand='GGLS' client=''>
        <updatecheck />
    </app>
</request>"
response="$(curl "https://tools.google.com/service/update2" --data "$req" 2> /dev/null )"
echo $response