const http = require('http')
const spawn = require('child_process').spawn
const createHandler = require('git-webhook-handler')
const handler = createHandler({ path: '/webhook', secret: 'webhook@git' })

handler.on('error', function(err){
	console.error('Error:', err.message)
})

handler.on('push', function(event){
	console.log(event.payload.repository.url)
	if(event.payload.repository.url.startsWith("https://gitee.com/src-oepkgs")){
		var msg = {
			"commit_id" : event.payload.after,
			"url" : event.payload.repository.url,
			"branch" : event.payload.ref.split('/')[-1]
		}
		console.log(msg)
		spawn('ruby', ['/js/src_oepkgs_push_hook.rb', JSON.stringify(msg)])
	} else {
		spawn('ruby', ['/js/push_hook.rb', event.payload.repository.url])
	}
})

handler.on('Merge Request Hook', function(event){
	if(event.payload.action != "open"){
		return
	}
	var msg = {
		"new_refs" : {
			"heads" : {
				"master" : event.payload.pull_request.head.sha
			}
		},
		"url" : event.payload.pull_request.base.repo.url,
		"submit_command" : {
			"pr_merge_reference_name" : event.payload.pull_request.merge_reference_name
		}
	}
	console.log(msg)
	spawn('ruby', ['/js/pr_hook.rb', JSON.stringify(msg)])
})

http.createServer(function(req, res){
	handler(req, res, function(err){
		res.statusCode = 404
		res.end('no such location')
	})
}).listen(20005)
