---
layout: mypost
title: 把emlog的图像验证码替换成Couldflare Turnstile
author: minc_nice_100
category: "时光机"
---

## 起因

最近几天网站被 DDOS 了(悲),第二波被撅的就是图像验证码.

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202408/thum-26d21724927604.png)

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/6b751725165819.png)

作为一位忠实的 Couldflare<del>白嫖</del>用户,鄙人花了一天时间把验证码全部换成 Couldflare Turnstile.

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/5e551725166150.png)

[您可以亲眼看到效果](https://web.archive.org/web/20250430040204/https://itedev.com/post/31#comment)

## 步骤

首先注册一个 Couldflare 账户,这个不再赘述.

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/35b11725165936.png)

转到 Turnstile 选项卡,点击添加站点.

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/24471725166241.png)

按照需求配置(每个配置项已经解释得很清楚了)

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/a20b1725166462.png)

到[这里](https://web.archive.org/web/20250430040204/https://developers.cloudflare.com/turnstile/get-started/client-side-rendering/)拷贝客户端集成代码

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/df7a1725166641.png)

首先我们要在网页头部(`<head></head>`)塞一个 js(事实上可以根据需求调整 js 的位置).

```html
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" defer></script>
```

来自文档的**警告**:

> api.js must be fetched from the exact URL stated below. Proxying or caching this file will likely result in Turnstile failing when future updates are released.
> 
> api.js 必须从下面所述的确切 URL 中获取。代理或缓存此文件可能会导致在发布未来更新时旋转门失败。

文档里面给出的集成代码如下,一般将其塞到表单的`<form></form>`里面:

```html
<div class="cf-turnstile" data-sitekey="yourSitekey" data-callback="javascriptCallback"></div>
```

我们可以为 div 加上其他`data-`属性(见文档),来控制呈现方式/深色模式/大小/回调等.

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/870b1725167074.png)

至此,前端的工作就完成了.

转到网站根目录的"/include/lib/common.php",在末尾的地方加上以下函数,记得替换`$secret = "`**`yourSecret`**`"`;

```php
// Cloudflare Turnstile 验证函数,函数接受"cf-turnstile-response"的 post 提交

function cloudflareTurnstile($response) {
    $secret = "yourSecret";
    $remoteip = getIp();
    $verifyResponse = file_get_contents("https://challenges.cloudflare.com/turnstile/v0/siteverify", false, stream_context_create([
        "http" => [
            "method" => "POST",
            "header" => "Content-type: application/x-www-form-urlencoded\r\n",
            "content" => http_build_query([
                "secret" => $secret,
                "response" => $response,
                "remoteip" => $remoteip
            ])
        ]
    ]));

    $responseData = json_decode($verifyResponse);
    if ($responseData->success) {
        return true;
    } else {
        return false;
    }

}
```

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/27b21725167593.png)

下面那个函数在后面的文章会出现(预告)

在需要的地方调用:

```php
// 以下的 Input 类为 emlog 特有,按需调整
$cfTurnstileResponse = Input::postStrVar('cf-turnstile-response');
cloudflareTurnstile($cfTurnstileResponse);
```

如果**`cloudflareTurnstile();`**返回**True**则验证成功,否则返回**False**

## 例子

- **评论(/include/lib/common.php:44)**

```php
    if (!ISLOGIN && Option::get('login_comment') === 'y') {
        $err = '请先完成登录，再发布评论';
    } elseif ($blogId <= 0 || empty($log)) {
        $err = '文章不存在';
    } elseif (Option::get('iscomment') == 'n' || $log['allow_remark'] == 'n') {
        $err = '该文章未开启评论';
    } elseif (User::isVisitor() && $Comment_Model->isCommentTooFast() === true) {
        $err = '评论发布太频繁';
    } elseif (empty($name)) {
        $err = '请填写昵称';
    } elseif (strlen($name) > 100) {
        $err = '昵称太长了';
    } elseif ($mail !== '' && !checkMail($mail)) {
        $err = '不是有效的邮箱';
    } elseif (empty($content)) {
        $err = '请填写评论内容';
    } elseif (strlen($content) > 60000) {
        $err = '内容内容太长了';
    } elseif (Option::get('comment_code') == 'y' && !cloudflareTurnstile($cfTurnstileResponse)) {
        $err = '验证失败';
    } elseif (empty($ua) || preg_match('/bot|crawler|spider|robot|crawling/i', $ua)) {
        $err = '非正常请求';
    }
```

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/e2b11725168267.png)

- **登录(/admin/account.php:46)**

```php
if (!cloudflareTurnstile(Input::postStrVar('cf-turnstile-response')) && Option::get('login_code') === 'y') {
    if ($resp === 'json') {
        Output::error('验证错误');
    }
    emDirect('./account.php?action=signin&err_ckcode=1');
}
```

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/2c051725168430.png)

- **注册(/admin/account.php:110)**

```php
if (!cloudflareTurnstile(Input::postStrVar('cf-turnstile-response')) && Option::get('login_code') === 'y') {
    if ($resp === 'json') {
        Output::error('验证错误');
    }
    emDirect('./account.php?action=signup&err_ckcode=1');
}
```

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/f06a1725168636.png)

- **重设密码(/admin/account.php:188)**

```php
if (!cloudflareTurnstile(Input::postStrVar('cf-turnstile-response')) && Option::get('login_code') === 'y') {
    if ($resp === 'json') {
        Output::error('验证错误');
    }
    emDirect('./account.php?action=reset&err_ckcode=1');
}
```

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/c19e1725168659.png)

所有后端代码保留了 Option::get(),可以在仪表板内控制是否开启

去看看仪表板吧

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/6cd31725168842.png)

![图像](https://web.archive.org/web/20250430040204im_/https://nas-alist.itedev.com/d/public/blog/202409/ac9f1725168853.png)