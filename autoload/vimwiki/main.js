// self-developped vimwiki page utilities by Alan Che 2022-2-9
// The Generated vimwiki html page leverage this to:
// set heading number
// show up the title in the front page center
$(document).ready(function() {
  $('pre.code').each(function(i, block) {
    console.log(block)
    hljs.highlightBlock(block);
  });
  // automatically numbering the h1 ~ h6 tags under #main-content
  (function(){
    var number = [0,0,0,0,0,0,0];
    var getIndex = function(elem) {
      return elem.tagName.slice(-1) - 1;
    };
    var collections = $("#main-content h1,#main-content h2,#main-content h3,#main-content h4,#main-content h5,#main-content h6");
    for (var i=0;i<collections.length;i++) {
      var obj = collections[i];
      // the digit location in number
      var idx = obj.tagName.slice(-1) - 1;
      if (obj.className.indexOf('justcenter') != -1) continue;
      if (obj.innerText == "Contents") continue
      if (obj.className.indexOf('nonumber') != -1) continue;
      // incremental current level digit
      number[idx++]++; 
      // clear the lower level digit
      while(idx < 6) {
        number[idx] = 0;
        idx++;
      }
      // conctat the levels
      var prefix = number.filter(function(i){return i}).join('.') + '.';
      obj.innerHTML = prefix + ' ' + obj.innerHTML;
    }
  })();
  // display the title in front of the main content
  (function() {
    $('<center><h1>' + $('title').text() + '</h1></center>').insertBefore($('#main-content'))
  })();
});
