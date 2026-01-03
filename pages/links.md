---
layout: mypost
title: Links
---

这是友链!!!!! 申请友链请评论区留言.

<audio title="雨落花开 - WillYoga王颢霖,欧阳潇枫.mp3" controls src="https://bucket.itedev.com/blog/9a5e1d5f77f948fbaa563bd899f255f6.mp3" ></audio>

```
名称：{{ site.title }}
描述：{{ site.description }}
地址：{{ site.domainUrl }}{{ site.baseurl }}
头像：https://static.itedev.com/favicon.ico
```

<ul>
  {%- for link in site.links %}
  <li>
    {%- if link.avatar %}
    <img src="{{ link.avatar }}" alt="{{ link.title }}" style="width: 50px; height: 50px; border-radius: 50%; display: inline-block; vertical-align: middle; margin-right: 10px;">
    {%- endif %}
    <div style="display: inline-block; vertical-align: middle;">
      <p><a href="{{ link.url }}" title="{{ link.desc }}" target="_blank" >{{ link.title }}</a></p>
      {%- if link.description %}
      <p style="margin: 5px 0 0 0; font-size: 14px; color: #666;">{{ link.description }}</p>
      {%- endif %}
    </div>
  </li>
  {%- endfor %}
</ul>