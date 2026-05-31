@echo off
node -e "const http=require('http'),fs=require('fs'),path=require('path');http.createServer((q,r)=>{const p=path.join(__dirname,(q.url.split('?')[0]==='/')?'index.html':q.url.split('?')[0]);fs.readFile(p,(e,d)=>{if(e){r.writeHead(404);return r.end();}r.writeHead(200);r.end(d);});}).listen(8080,()=>console.log('http://localhost:8080'));"
