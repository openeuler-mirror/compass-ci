# Access the testbox

Before you access the testbox, you need apply an account first, and then submit a job.

How to apply the account, reference to:

  apply-account.md

How to borrow a testbox， reference to:

  borrow-machine.en.md

## conditions for user to access the testbox

In two conditions, user need to access the testbox:

  - borrow a machine.
  - submit a job with option '-i ssh-on-fail.yaml', the testbox will enable user to access if the job is running in failures.

For the conditions above, the server will automatically send a email with access method to user to enable user to access the testbox.

User can access the testbox with the command/URL in the email content.

Examples:

  Command line:

	ssh root@123.60.114.28 -p 22222

  Web URL：

	https://jumper.compass-ci.openeuler.org/?hostname=123.60.114.28&username=root&port=22222

Security remind:
  According to the security regulations, the server need to add user's IP to the  white list if user want to access the testbox with command line method. This way will be disabled in the future.
  Suggest use the web URL to access the testbox for public newwork users.

## Access authorization

The testbox is only allowed to access with secret key.

A public key was firstly uploaded to the server when user send the 'apply account' email.
The public key will be registered to the testbox when user submit a job.
Just use the matching private key to access the test box.

## Update secret key

It will lead to access failures case user missed his/her private sccret key.
In this case, user need to update his/her public key to the server.

We provide variety method for user to update the public key to the server side:

1. Upload through submitting a borrow job
   Generate new secret pairs(Linux). A borrowing job will automatically upload the public key($HOME/.ssh/id_rsa.pub) to the server side.

2. Upload through email
   Re-send the 'apply account' email with the public key as the attachment, the public key will automatically updated to the server side.

3. Contact the technical support staff to update the public key
   Offer the public key to the technical support staff to update it manually.

Submit new job after successfully updated the public key.
Just use the private key to access the test box.
