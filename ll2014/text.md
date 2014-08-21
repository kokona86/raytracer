# Heroku <small>で</small> Gauche<br/><small><small>（あるいは好きな言語なんでも）</small></small>

Lightweight Language Diver 2014

久井 亨 Toru Hisai @torus

.fx: titleslide

---

# 自己紹介

-   久井 亨（ひさい とおる）
-   都内のゲーム制作会社のサーバサイドエンジニア
    -   普段は Node.js
-   一応 CPAN author（3 個だけ）

---

# あらすじ

1.  Heroku のしくみ
2.  Docker でビルド
3.  Gauche でウェブアプリ

---

# <img src="./heroku-logo-light-300x100.png" />

（関係者の方いたらツッコミお願いします）

.fx: titleslide

---

# Heroku

<img src="./Y-combinator-logo.gif"/>

-   Y Combinator から生まれた PaaS
-   Git でスマートにデプロイ
    -   `git push heroku master`
-   アメリカ西海岸でブイブイいわせたい

---

## 様々な言語、フレームワークに対応
<img src="./heroku-languages.png"/>


---

## しかし
-   Gauche はない
-   他の Scheme 処理系もない

<img src="./gauche-checkin-guile.png"/>

---

<img src="./aa-shuryo.png"/>

.fx: titleslide

---

## Y Combinator にかぶれる
<img src="./4822249468.jpg" />

---

<img src="./aa-saikai.png"/>

.fx: titleslide

---

<img src="./Earth-crust-cutaway-heroku.svg" />

.fx: imageslide

---

# The Celadon Cedar Stack
-   Heroku のデフォルトスタック
    -   ベース OS: Ubuntu 10.04
    -   ライブラリ
    -   言語実行ランタイム
-   この上にのせれば動く……！

---

# Slug
<img src="./canstockphoto17731474.jpg" />


---

# Slug
-   実行可能な Cedar アプリケーションを tar アーカイブしたもの
-   作成時の約束はこれだけ：
    -   ディレクトリ名：`app`
    -   コマンド：`tar czfv slug.tgz ./app`
        -   `./` が重要！

---

## アーカイブ

<img src="./archiving-slug.png" />


---

## Cedar Stack に載せる

<img src="./slug-on-heroku.png" />

---

# デモ
[gauche-example.herokuapp.com](http://gauche-example.herokuapp.com)

.fx: titleslide

---

# ビルド/デプロイ/リリース

-   Git は使わない
    -   Slug を作る
    -   Web API でアップロード
    -   Web API でリリース

---

## Ubuntu 10.04 でコンパイル
-   Mac や Ubuntu 14.04 でコンパイルしても動かない
    -   バイナリの形式が違う
    -   glibc のバージョンが違う
-   `heroku run bash` はまどろっこしい
    -   One-off dyno は別料金がかかる
-   そこで……

---

<img src="./large_v-trans.png" />

.fx: imageslide

---

## Docker を使うと簡単

<img src="./build-deploy.png" />

-   Dockerfile を作るだけ

---

## Dockerfile

仮想マシンにいろいろインストールして<br/>
イメージを作る。

-   Ubuntu 10.04
-   Gauche 0.9.4 & HEAD
-   Gauche-makiki
-   Gauche-gl

---

## Dockerfile - Ubuntu 10.04

    !sh
    FROM ubuntu:10.04
    MAINTAINER Toru Hisai <toru@torus.jp>
    
    RUN apt-get update -y
    RUN apt-get install -y wget gcc
    RUN apt-get install -y zlib1g-dev slib
    RUN apt-get install -y make autoconf

---

## Dockerfile - Gauche 0.9.4

    !sh
    WORKDIR /tmp
    RUN wget http://prdownloads.sourceforge.net/
                            gauche/Gauche-0.9.4.tgz
    RUN tar xvfz Gauche-0.9.4.tgz
    
    WORKDIR Gauche-0.9.4
    RUN ./configure
    RUN make
    RUN make check
    RUN make install

---

## Dockerfile - Gauche HEAD

（あらかじめ GitHub からクローンしておく）

    !sh
    ADD Gauche /tmp/Gauche
    WORKDIR /tmp/Gauche
    RUN ./DIST gen
    RUN ./configure --prefix=/opt/gauche
    RUN make
    RUN make check
    RUN make install
    ENV PATH /opt/gauche/bin:$PATH

---

## Dockerfile - Gauche-makiki

（あらかじめ GitHub からクローンしておく）

    !sh
    ADD Gauche-makiki /tmp/Gauche-makiki
    WORKDIR /tmp/Gauche-makiki
    RUN ./DIST gen
    RUN ./configure --prefix=/opt/gauche
    RUN make
    RUN make check
    RUN make install

---

## Dockerfile - Gauche-gl

（あらかじめ GitHub からクローンしておく）

    !sh
    ADD Gauche-gl /tmp/Gauche-gl
    WORKDIR /tmp/Gauche-gl
    RUN ./DIST gen
    RUN ./configure --prefix=/opt/gauche
    RUN make
    RUN make check
    RUN make install

---

## Dockerfile - バイナリ生成

エントリーポイントでバイナリをダンプする。

    !sh
    WORKDIR /opt
    ENTRYPOINT tar cf - gauche

---

## イメージのビルドと起動

<img src="./docker-app-generation.png" />

    !sh
    $ docker build -t gauche_heroku_app .
    $ docker run gauche_heroku_app |\
                     (cd app && tar xvf -)

---

# Gauche <small>でウェブアプリ</small>

<img src="./1280px-Makiki-Agriculturebldg-courtyard.jpg" />


---

## 必要な物
-   Gauche の開発版
    -   プロダクション環境でも最新版を使いたい
    -   ビルドに Gauche のリリース版が必要
-   Gauche-makiki
    -   Sinatra 風ウェブフレームワーク
-   Gauche-gl
    -   ベクトル計算に使用

---

## Gauche-makiki

    !scheme
    (use makiki)
    
    (define-http-handler "/render.ppm"
      (^[req app]
        (random-source-randomize! default-random-source)
        (let ([param-size (request-param-ref req "size")]
              [param-frame (request-param-ref req "frame")])
          (let ([opt-size (if param-size #`"-s ,param-size" "")]
                [opt-frame (if param-frame #`"-f ,param-frame" "")]
                [outfile #`"out,(random-integer 1000000).jpg"])
            (respond/ok req
                        (with-output-to-string
                          (lambda ()
                            ((global-variable-ref raytracer-mod 'main)
                             `(self ,@(string-split opt-size #/\s+/)
                                    ,@(string-split opt-frame #/\s+/)))))
                        :content-type "image/x-portable-pixmap")))))


---

## リリースまでの道のり

-   Slug を作る
-   process_types を考える
-   Slug をアロケート
-   Slug をアップロード
-   環境変数の設定
-   リリース

---

## Slug を作る

    !make
    slug.tgz: $(SOURCES) ../docker/gauche/app/gauche
    	rm -rf app
    	mkdir app
    	cp -R ../docker/gauche/app/gauche app/gauche
    	cp -R $(SOURCES) app/
    	tar cfz $@ ./app

-   Docker で作った app ディレクトリ
-   アプリケーション

をコピーしてアーカイブ。

---

## process_types

-   Procfile の内容に相当するもの

<!-- dummy -->

    !javascript
    {"process_types":
      {"web":"./gauche/bin/gosh
          -I ./gauche/share/gauche-0.9/0.9.4/lib
          -I ./gauche/share/gauche-0.9/site/lib
          -I ./gauche/lib/gauche-0.9/0.9.4/
                             x86_64-unknown-linux-gnu/
          -I ./gauche/lib/gauche-0.9/site/
                             x86_64-unknown-linux-gnu/
          -I ./
          index.scm --port=$PORT"}}

---

## Slug をアロケート

    !make
    slug.json: slug.tgz
    	curl -X POST \
    	-H 'Content-Type: application/json' \
    	-H 'Accept: application/vnd.heroku+json; version=3' \
    	-d '{"process_types":{"web":"./gauche/bin/gosh \
            -I ./gauche/share/gauche-0.9/0.9.4/lib \
            -I ./gauche/share/gauche-0.9/site/lib \
            -I ./gauche/lib/gauche-0.9/0.9.4/x86_64-unknown-linux-gnu/ \
            -I ./gauche/lib/gauche-0.9/site/x86_64-unknown-linux-gnu/ \
            -I ./ index.scm --port=$$PORT"}}' \
    	-n https://api.heroku.com/apps/$(APPNAME)/slugs > $@

---

### レスポンス：Slug についての情報

    !javascript
    {
      "blob":{
        "method":"put",
        "url":"https://s3-external-1.amazonaws.com/herokuslugs/heroku.com/v1/7e4d9819-833f-4aec-9d6f-af112eacd530?AWSAccessKeyId=AKIAJWLOWWHPBWQOPJZQ&Signature=Wu5b7n7S6NgxBYGXolq6AdBoqSY%3D&Expires=1406388246"
      },
      "buildpack_provided_description":null,
      "commit":null,
      "created_at":"2014-07-26T14:24:06Z",
      "id":"7e4d9819-833f-4aec-9d6f-af112eacd530",
      "process_types":{
        "web":"./gauche/bin/gosh -I ./gauche/share/gauche-0.9/0.9.4/lib -I ./gauche/share/gauche-0.9/site/lib -I ./gauche/lib/gauche-0.9/0.9.4/x86_64-unknown-linux-gnu/ -I ./gauche/lib/gauche-0.9/site/x86_64-unknown-linux-gnu/ -I ./ index.scm --port=$PORT"
      },
      "size":null,
      "updated_at":"2014-07-26T14:24:06Z"
    }

---

## Slug アップロード

    !make
    upload-slug: slug.json
    	curl -X PUT \
    	-H "Content-Type:" \
    	--data-binary @slug.tgz \
    	`gosh extract-slug-url.scm < slug.json`

-   `extract-slug-url.scm` は先のレスポンスから `blob` の `url` を取り出す
    -   `https://s3-external-1.amazonaws.com/herokuslugs/...`

---
## 環境変数の設定

-   環境変数 `LD_LIBRARY_PATH` を設定
    -   Gauche のライブラリがリンクできるように
    -   相対パスになってるのがミソ

<!-- dummy -->

    !sh
   	$ heroku config:set LD_LIBRARY_PATH=./gauche/lib \
        --app=$APPNAME

---

## リリース

    !make
    release: upload-slug
    	curl -X POST \
    	-H "Accept: application/vnd.heroku+json; version=3" \
    	-H "Content-Type: application/json" \
    	-d '{"slug":"'`gosh extract-slug-id.scm \
                                        < slug.json`'"}' \
    	-n https://api.heroku.com/apps/$(APPNAME)/releases

-   `extract-slug-id.scm` は先のレスポンスから Slug の ID を取り出す
    -   `7e4d9819-833f-4aec-9d6f-...`

---

# デモ

（Slug のアップロードとリリース）

.fx: titleslide

---

## レイトレーサの原理

<img src="./Ray_trace_diagram.svg" />

---

## 分散レイトレーシング
-   スクリーンを分割してレンダリング
-   ベクトル計算に Gauche-gl を使用

---

# デモ
[gauche-raytracer.herokuapp.com/renderppm.html](http://gauche-raytracer.herokuapp.com/renderppm.html)

.fx: titleslide

---

# Dyno
-   Dyno を増やすと簡単にスケールアウト
-   秒単位で料金精算
    -   $.05/時間
    -   1 アプリにつき 750 dyno 時間/月は無料
    -   One-off dyno は別途料金がかかる

---

# デモ
[dashboard.heroku.com](https://dashboard.heroku.com/apps/gauche-raytracer/resources)

.fx: titleslide

---

# 別の方法

-   Buildpack を作る
    -   Git でデプロイできるようになる
    -   しょっちゅうリビルドする場合は却って面倒

---

# まとめ

-   Heroku は割となんでも動かせる
-   Docker を使えばビルドもらくちん
-   使わないときはこまめに Dyno を消しておく
    -   料金が節約できる
-   ソースコード：
    -   https://github.com/torus/raytracer
    -   https://github.com/torus/gauche-heroku-cedar

---

# 参考資料：

-   [Creating slugs from scratch | Heroku Dev Center](https://devcenter.heroku.com/articles/platform-api-deploying-slugs)
-   [Usage & Billing | Heroku Dev Center](https://devcenter.heroku.com/articles/usage-and-billing)
-   [Dockerfile - Docker Documentation](https://docs.docker.com/reference/builder/)
-   [Lesson 1: Writing a Simple Raytracer » www.scratchapixel.com](http://scratchapixel.com/lessons/3d-basic-lessons/lesson-1-writing-a-simple-raytracer/)
-   [Gauche on Heroku - ellipsis](http://nazuma.hatenablog.com/entry/2012/12/08/014436)
