---
layout: post
title: 使用 Cloudflare Zero Trust 保护你的应用程序
author: minc_nice_100
tags: ["Cloudflare", "Zero Trust"]
---

由于社团的需要, 站长需要暴露机器上的一些端点, 并进行保护以免未经授权的访问, 由于站长使用 Cloudflare Tunnel 进行内网穿透, 因此需要使用 Cloudflare Zero Trust 进行保护.

*实际上是因为懒, 我不想再实现额外的安全层👍*

> ##### TIP
>
> 本文假设你已经熟练掌握 Cloudflare 的使用, 并且完成 Zero Trust 的注册.
> 请提前添加好需要的解析记录和和穿透一类的, 本文不再赘述.
{: .block-tip }

## 添加可重用策略
首先, 我们**可以**创建一个可重用策略, 你需要转到这一个页面 `/access/policies?tab=reusable`, 其在 Zero Trust 仪表板中.

![如图所示](https://bucket.itedev.com/blog/782b6185b46d4ef39a652b8af05f0f10.avif)

然后我们点击**添加策略**按钮,并且添加 **Any Access Service Token** 与 **Valid Certificate** 两个包括选择器, 按需添加其他内容(推荐新建一个可重用策略).

![选择器](https://bucket.itedev.com/blog/9403b1bd5102498e8222ffa355514ec6.avif)

别忘记给它一个名称, 然后点击**保存**.

## 添加应用程序
接下来, 我们需要新建一个应用程序, 转到 `/access/apps`, 然后点击**添加应用程序**按钮, 并选择应用程序类型(本文以自托管应用程序为例).
![选择应用程序类型](https://bucket.itedev.com/blog/e14e870f86c4455e914e10451438bb61.avif)

然后在 Access 策略一栏选择刚才创建的可重用策略, 为应用程序起个名字, 编辑其他需要的设置, 然后点击下一步, 一直来到高级设置.
![Access 策略](https://bucket.itedev.com/blog/976e2983923843b9b5a6967256657c44.avif)

认证填写此页的所有内容, 然后点击保存. 
![CROS 设置](https://bucket.itedev.com/blog/38ad0d1fef2a4c388cb072ad4ec512f9.avif) 
![服务身份验证策略的 401 响应](https://bucket.itedev.com/blog/6b54714e241940b6ad971b1039e323ab.avif)

此时, 我们完成了应用程序的设置, 访问目标端点, 理论上我们会看到下面的内容:
![Forbidden](https://bucket.itedev.com/blog/08f51da60ece434d9a8d3ec369663800.avif)

## 创建服务令牌/证书
最后, 我们需要创建一个服务令牌(当然的你也可以丢一组根证书给 Zero Trust, 让它自己签短期证书拿来授权, 此处不演示), 用以访问应用程序.
转到 `/access/service-auth`, 点击创建一个服务令牌.

![创建服务令牌](https://bucket.itedev.com/blog/5ed17af7beeb41f393c6b42ebb986fd4.avif)

起个名字并选择有效期(不推荐创建无限期令牌, 否则您可能遭老罪..迫真), 然后点击**创建**.
此时你会获得一组类似下方的令牌:
```json
{
    "CF-Access-Client-Id": "***.access",
    "CF-Access-Client-Secret": "***"
}
```

这是两个标头, 在请求里带上就行.
```bash
curl -H "CF-Access-Client-Id: ***.access" -H "CF-Access-Client-Secret: ***" https://example.com/api/endpoint
```

## 总结
至此, 你已经学会如何使用 Cloudflare Zero Trust 保护你的端点, 保护好你的令牌/证书(大声!!).

欢迎找我讨论: [Contact](/contact/)

## 后记
文字里所提的端点是暴露给 Sean (鲤鱼🐟)他们的一个社团的, [你可以到这里找🐟玩](https://makabaka1880.xyz/)

其评论区用不了, 那是我还没修好(托管在我这www).