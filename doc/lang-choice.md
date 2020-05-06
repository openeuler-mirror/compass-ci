shell
=====

## Pro
- widely available
- quick & dirty

## Con
- don't grow large

## Main scenarios
- run in test box


ruby
====

## Pro
- human efficient
- human friendly
- no compile
- gems: good coverage
- ri: nice doc
- pry: convenient to try out
- google: rich experiences

## Con
- slow
- bloated for small devices

## Main scenarios
- extend existing code base
- end user tools
  - easy to distribute
  - transparent and trusted
- server side tools (not performance sensitive)


crystal
=======

## Pro
- ruby like
- human efficient
- machine efficient
- suitable for large projects
  - static type
  - compile checked
- easy to deploy (static linking)

## Con
- pre-release
- slow compile
- sharks: only cover core libs
- little aids like ri/pry/google

## Main scenarios
- micro-services, eg.
  - post processing
    - wrap stats/* in classes in a long run service
  - git service
    - use libgit2 + git cli wrapper 
    - to deprecate ruby-git
    - ruby-git adds complexity. Either use libgit2 for better performance, or
      wrap plain git cli commands to be reuse knowledge and cli git docs.
- run in testbox (beyond shell capabilities)
  - tests/*
  - testbox side framework

python
======

## Main scenarios
- library that greatly helps
  - fbtftp
  - data analyze and plot?

javascript
==========

## Main scenarios
- web interface
  - d3.js visualization
