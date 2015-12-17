async = require 'async'
GitHubApi = require 'github'
credentials = require './credentials'

log = (o) ->
  console.log require('util').inspect(o, 0, 10, 1)

github = new GitHubApi
  version: '3.0.0'
  # debug: true
  protocol: 'https'
  timeout: 5000
  # headers:
  #   'user-agent': 'My-Cool-GitHub-App' // GitHub is happy with a unique user agent

github.authenticate
  type: 'basic'
  username: credentials.username
  password: credentials.password

counts =
  given: {}
  received: {}

countLGTMsForRepo = (counts, {org, repo}, cb) ->
  hasNextPage = true
  maxPages = 11
  page = 0
  async.whilst ->
    console.log 'pages', page, hasNextPage, page < maxPages
    return hasNextPage || page < maxPages
  , (nextCb) ->
    msg =
      user: org
      repo: repo
      state: 'closed'
      per_page: 100
      page: page
    github.pullRequests.getAll msg, (err, prs) ->
      return nextCb err if err
      prsByUser = {}
      for pr in prs
        continue unless (creator = pr.user?.login)
        prsByUser[creator] ||= []
        prsByUser[creator].push
          number: pr.number
          title: pr.title
          creator: creator
          url: pr.html_url
      log prsByUser
      incrementCountForPRs counts, prsByUser, {org, repo}, (err) ->
        return nextCb err if err
        page++
        log counts
        for user, count of counts.given
          received = counts.received[user] || 0
          console.log user, ',', count, ',', received, ',', count + received
        for user, count of counts.received when !counts.given[user]
          console.log user, ',', 0, ',', received, ',', received
        return nextCb()
  , (err) ->
    return cb err if err


incrementCountForPRs = (counts, prsByUser, {org, repo}, cb) ->
  async.eachSeries Object.keys(prsByUser), (user, userCb) ->
    console.log 'Fetching PRs for user', user, '...'
    prs = prsByUser[user]
    async.eachSeries prs, (pr, prCb) ->
      findLGTMComment {org, repo, pr}, (err, result) ->
        console.log result
        if result?.lgtm
          reviewer = result.reviewer
          counts.given[reviewer] ||= 0
          counts.given[reviewer] += 1
          counts.received[user] ||= 0
          counts.received[user] += 1
        else
          console.log 'No LGTM found', pr
        return prCb()
    , userCb
  , cb

findLGTMComment = ({org, repo, pr}, cb) ->
  github.issues.getComments {user: org, repo, number: pr.number}, (err, comments) ->
    return cb err if err
    for comment in comments when comment?.body
      continue unless /LGTM/.test(comment.body) || /lgtm/.test(comment.body) || /LGreatTM/.test(comment.body)
      reviewer = comment.user?.login
      return cb null, {reviewer, lgtm: comment.body}
    return cb()

countLGTMsForRepo counts, {org: 'lever', repo: 'hire2'}, (err) ->
  log counts
  for user, count of counts.given
    received = counts.received[user] || 0
    console.log user, ',', count, ',', received, ',', count + received
  for user, count of counts.received when !counts.given[user]
    console.log user, ',', 0, ',', received, ',', received

  console.log err if err
  process.exit()
