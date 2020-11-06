const http = require('http')
const spawn = require('child_process').spawn
const createHandler = require('git-webhook-handler')
// if users want to use webhook, they need to config webhook on their code warehouse('gitee.com' or 'github.com'),
// and use url: http://183.134.196.212:11301/webhook, secret: webhook@git.
const handler = createHandler({ path: '/webhook', secret: 'webhook@git' })

handler.on('error', function(err){
	console.error('Error:', err.message)
})

handler.on('push', function(event){
	console.log(event.payload.repository.url)
	spawn('ruby', ['push_hook.rb', event.payload.repository.url])
})

http.createServer(function(req, res){
	handler(req, res, function(err){
		res.statusCode = 404
		res.end('no such location')
	})
}).listen(11301)
