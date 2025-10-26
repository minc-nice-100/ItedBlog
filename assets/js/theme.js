// Noctua v3 theme JS
document.addEventListener('DOMContentLoaded', function(){
  // Respect prefers-color-scheme
  try {
    const prefersLight = window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches;
    if(prefersLight){
      document.documentElement.classList.add('light');
    }
  } catch(e){}

  // Auto-add lazyload attributes to markdown images
  document.querySelectorAll('.post-body img').forEach(function(img){
    if(!img.classList.contains('lazyload')){
      img.setAttribute('data-src', img.getAttribute('src'));
      img.setAttribute('loading', 'lazy');
      img.classList.add('lazyload');
      // keep src as placeholder to avoid broken images when lazysizes not loaded
      img.removeAttribute('src');
    }
  });

  // init highlight.js if available
  if(window.hljs){
    try{ hljs.highlightAll(); }catch(e){}
  }

  // init KaTeX auto-render (if present)
  if(window.renderMathInElement){
    try{ renderMathInElement(document.body); }catch(e){}
  }

  // init search when simple-jekyll-search is present
  if(window.SimpleJekyllSearch){
    try{
      SimpleJekyllSearch({
        searchInput: document.getElementById('search-input'),
        resultsContainer: document.getElementById('results-container'),
        json: '/search.json',
        limit: 10,
        fuzzy: false,
        searchResultTemplate: '<li><a href="{url}">{title}</a> <small style="color:var(--muted)">{date}</small></li>'
      });
    }catch(e){}
  }

});
