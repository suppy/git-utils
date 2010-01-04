#!/usr/bin/env ruby

require 'rubygems'
gem 'test-unit'
require 'test/unit'

require 'tempfile'

require 'commit-email'

class GitCommitMailerTest < Test::Unit::TestCase
  def execute(command, directory=@git_dir)
    GitCommitMailer.execute(command, directory)
  end

  def git(command, repository_dir=@repository_dir)
    sleep 1.1 if command =~ /\A(commit|merge) / #wait for the timestamp to tick
    trash_post_receive_output if command =~ /\Apush/

    if command =~ /\Ainit/
      execute("git #{command}", repository_dir)
    else
      execute "git --git-dir=#{repository_dir} #{command}"
    end
  end

  def temporary_name
    prefix = 'git-'
    t = Time.now.strftime("%Y%m%d")
    path = "#{prefix}#{t}-#{$$}-#{rand(0x100000000).to_s(36)}"
  end

  def config_user_info
    git 'config user.name "User Name"'
    git 'config user.email "user@example.com"'
  end

  def register_hook_to_origin
    @post_receive_stdout = @origin_repository_dir + 'post-receive.stdout'
    if File.exist?(@origin_repository_dir + "hooks/post-receive.sample")
      FileUtils.mv(@origin_repository_dir + "hooks/post-receive.sample",
                   @origin_repository_dir + "hooks/post-receive")
    end
    execute "chmod +x hooks/post-receive", @origin_repository_dir
    append_line(@origin_repository_dir + "hooks/post-receive", "cat >> #{@post_receive_stdout}")
  end

  def create_repository
    while File.exist?(@test_dir = Dir.tmpdir + "/" + temporary_name + "/")
    end
    FileUtils.mkdir @test_dir
    @origin_repository_dir = @test_dir + 'origin/'
    FileUtils.mkdir @origin_repository_dir
    git 'init --bare', @origin_repository_dir
    register_hook_to_origin

    @git_dir = @test_dir + 'repo/'
    @repository_dir = @git_dir + '.git/'
    FileUtils.mkdir @git_dir
    git 'init', @git_dir
    config_user_info
    git "remote add origin #{@origin_repository_dir}"
  end

  def each_post_receive_output
    File.open(@post_receive_stdout, 'r') do |file|
      while line = file.gets
        old_revision, new_revision, reference = line.split
        yield old_revision, new_revision, reference
      end
    end
  end

  def process_single_ref_change(*args)
    @push_mail, @commit_mails = @mailer.process_single_ref_change(*args)
  end

  def trash_post_receive_output
    FileUtils.rm(@post_receive_stdout) if File.exist?(@post_receive_stdout)
  end

  def delete_repository
    return if ENV['DEBUG'] == 'yes'
    FileUtils.rm_r @test_dir
  end

  def save_environment_variables(names)
    @saved_environment_variables = {}
    names.each do |name|
      @saved_environment_variables[name] = ENV[name]
      ENV[name] = nil
    end
  end

  def restore_environment_variables
    @saved_environment_variables.each do |name, value|
      ENV[name] = value
    end
  end

  def setup
    @is_debug_mode = true if ENV['DEBUG'] == 'yes'
    save_environment_variables(['GIT_AUTHOR_NAME',
                                'GIT_AUTHOR_EMAIL',
                                'GIT_COMMITTER_NAME',
                                'GIT_COMMITTER_EMAIL',
                                'EMAIL'])
    create_repository
  end

  def teardown
    delete_repository
    restore_environment_variables
  end

  def zero_revision
    '0' * 40
  end

  def create_mailer(argv)
    @mailer = GitCommitMailer.parse_options_and_create(argv.split)
  end

  def create_default_mailer
    create_mailer("--repository=#{@origin_repository_dir} " +
                  "--name=sample-repo " +
                  "--from from@example.com " +
                  "--error-to error@example.com to@example")
  end

  def black_out_sha1(string)
    string.gsub(/[0-9a-fA-F]{40}/, "*" * 40).
           gsub(/[0-9a-fA-F]{7}/, "*" * 7)
  end

  def black_out_date(string)
    date_format1 = '20[0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9] ' +
                   '[+-][0-9]{4} \([A-Z][a-z][a-z], [0-3][0-9] [A-Z][a-z][a-z] 20..\)'
    date_format2 = '20[0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9] ' +
                   '[+-][0-9]{4}'
    date_format3 = '^Date: [A-Z][a-z][a-z], [0-3][0-9] [A-Z][a-z][a-z] 20[0-9][0-9] ' +
                   '[0-2][0-9]:[0-5][0-9]:[0-5][0-9] [+-][0-9]{4}'
    string.gsub(Regexp.new(date_format1), '****-**-** **:**:** +**** (***, ** *** ****)').
           gsub(Regexp.new(date_format2), '****-**-** **:**:** +****').
           gsub(Regexp.new(date_format3), 'Date: ***, ** *** **** **:**:** +****')
  end

  def black_out_mail(mail)
    mail = black_out_sha1(mail)
    mail = black_out_date(mail)
  end

  def read_file(file)
    File.open(file) do |file|
      return file.read
    end
  end

  def create_file(filename, content)
    File.open(@git_dir + filename, 'w') do |file|
      file.puts(content)
    end
  end

  def commit_new_file(filename, content, message=nil)
    create_file(filename, content)

    message ||= "This is a auto-generated commit message: added #{filename}"
    git "add #{filename}"
    git "commit -m \"#{message}\""
  end

  def assert_mail(expected_mail_filename, tested_mail)
    assert_equal(read_file('fixtures/'+expected_mail_filename), black_out_mail(tested_mail))
  end

  def last_mails
    push_mail, commit_mails = nil, []
    each_post_receive_output do |old_revision, new_revision, reference|
      push_mail, commit_mails = process_single_ref_change(old_revision, new_revision, reference)
    end
    [push_mail, commit_mails]
  end

  def prepend_line(file_name, line)
    execute "sed -i -e '1 s/^/'#{Shellwords.escape(line)}'\\n/' #{Shellwords.escape(file_name)}"
  end

  def append_line(file_name, line)
    execute "echo #{Shellwords.escape(line)} >> #{Shellwords.escape(file_name)}"
  end

  def insert_line(file_name, line, offset)
    execute "sed -i -e '#{offset} s/^/'#{Shellwords.escape(line)}'\\n/' #{Shellwords.escape(file_name)}"
  end

  def test_single_commit
    create_default_mailer
    sample_filename = 'sample_file'

    file_content = <<EOF 
This is a sample text file.
This file will be modified to make commits.
EOF
    commit_new_file(sample_filename, file_content, "an initial commit")

    git 'push origin master'

    push_mail, commit_mails = last_mails

    assert_mail('test_single_commit.push_mail', push_mail)
    assert_mail('test_single_commit', commit_mails[0])
  end

  def test_push_with_merge
    create_default_mailer
    sample_file = 'sample_file'
    sample_branch = 'sample_branch'

    file_content = <<EOF
This is a sample text file.
This file will be modified to make commits.
Firstly, it'll be appended with some lines in a non-master branch.
Secondly, it'll be prepended and inserted with some lines in the master branch.
Finally, it'll get merged.
EOF
    commit_new_file(sample_file, file_content, "added a sample text file")

    git "branch #{sample_branch}"
    git "checkout #{sample_branch}"
    append_line(sample_file, "This line is appended in '#{sample_branch}' branch (1)")
    git "commit -a -m \"a sample commit in '#{sample_branch}' branch (1)\""
    git "tag -a -m 'This is a sample tag' sample_tag"

    git "checkout master"
    prepend_line(sample_file, "This line is appended in 'master' branch. (1)")
    git "commit -a -m \"a sample commit in 'master' branch (1)\""
    insert_line(sample_file, "This line is inserted in 'master' branch. (2)", 5)
    git "commit -a -m \"a sample commit in 'master' branch (2)\""

    git "push --tags origin #{sample_branch} master"

    git "checkout #{sample_branch}"
    append_line(sample_file, "This line is appended in '#{sample_branch}' branch (2)")
    git "commit -a -m \"a sample commit in '#{sample_branch}' branch (2)\""
    append_line(sample_file, "This line is appended in '#{sample_branch}' branch (3)")
    git "commit -a -m \"a sample commit in '#{sample_branch}' branch (3)\""

    git "checkout master"
    git "merge #{sample_branch}"

    git "push origin master #{sample_branch}"

    pushes = []
    each_post_receive_output do |old_revision, new_revision, reference|
      pushes << process_single_ref_change(old_revision, new_revision, reference)
    end

    master_ref_change = pushes[0]
    master_push_mail = master_ref_change[0]
    master_commit_mails = master_ref_change[1]

    assert_mail('test_push_with_merge.push_mail', master_push_mail)
    assert_equal(4, master_commit_mails.length)
    assert_mail('test_push_with_merge.1', master_commit_mails[0])
    assert_mail('test_push_with_merge.2', master_commit_mails[1])
    assert_mail('test_push_with_merge.3', master_commit_mails[2])
  end

  def test_diffs_with_trailing_spaces
    create_default_mailer
    sample_file = 'sample_file'

    file_content = <<EOF
This is a sample text file.
This file will be modified to make commits.
    
In the above line, I intentionally left some spaces.
EOF
    commit_new_file(sample_file, file_content, "added a sample file")
    git 'push origin master'

    execute "sed -r -i -e 's/ +$//' #{sample_file}"
    git 'commit -a -m "removed trailing spaces"'

    git 'push'

    push_mail, commit_mails = last_mails

    assert_mail('test_diffs_with_trailing_spaces', commit_mails[0])
  end

  def test_diffs_with_multiple_hunks
    create_default_mailer
    sample_file = 'sample_file'

    file_content = <<EOF
This is a sample text file.
This file will be modified to make commits.

In the above line, I intentionally left some spaces.
some filler text to make two hunks with diff
some filler text to make two hunks with diff
some filler text to make two hunks with diff
some filler text to make two hunks with diff
some filler text to make two hunks with diff
some filler text to make two hunks with diff
some filler text to make two hunks with diff
EOF
    commit_new_file(sample_file, file_content, "added a sample file")
    git 'push origin master'

    prepend_line(sample_file, 'a prepended line')
    append_line(sample_file, 'an appended line')
    git 'commit -a -m "edited to happen multiple hunks"'

    git 'push'

    push_mail, commit_mails = last_mails

    assert_mail('test_diffs_with_multiple_hunks', commit_mails[0])
  end

  def test_diffs_with_multiple_files
    create_default_mailer

    2.times do |i|
      file_name = "file_#{i.to_s}"
      file_content = "text in #{file_name}"
      commit_log = "added #{file_name}"
      create_file(file_name, file_content)
      git "add #{file_name}"
    end
    git "commit -a -m 'added multiple files'"
    git 'push origin master'

    push_mail, commit_mails = last_mails

    assert_mail('test_diffs_with_multiple_files', commit_mails[0])
  end

  def test_nested_merges
    create_default_mailer
    sample_file = 'sample_file'
    first_branch = 'first_branch'
    second_branch = 'second_branch'

    file_content = <<EOF
This is a sample text file.
This file will be modified to make commits.
This line is needed to assist the auto-merge algorithm.
EOF
    commit_new_file(sample_file, file_content, "added a sample file")
    git 'push origin master'

    git "branch #{first_branch}"
    git "checkout #{first_branch}"
    append_line(sample_file, "This line is appended in '#{first_branch}' branch.")
    git "commit -a -m \"a sample commit in '#{first_branch}' branch\""
    git "push"

    git "checkout master"
    execute "sed -i -e '1 s/This/THIS/' #{sample_file}"
    git "commit -a -m \"a sample commit in master branch: This => THIS\""
    git "push"

    git "branch #{second_branch}"
    git "checkout #{second_branch}"
    prepend_line(sample_file, "This line is prepnded in '#{second_branch}' branch.")
    git "commit -a -m \"a sample commit in '#{second_branch}' branch\""
    git "push"

    git "checkout master"
    execute "sed -i -e '2 s/file/FILE/' #{sample_file}"
    git "commit -a -m \"a sample commit in master branch: file => FILE\""
    git "push"
    

    git "checkout #{first_branch}"
    git "merge #{second_branch}"

    git "checkout master"
    git "merge #{first_branch}"
    git "push"

    push_mail, commit_mails = last_mails

    assert_mail('test_nested_merges.push_mail', push_mail)
    assert_mail('test_nested_merges.1', commit_mails[0])
    assert_mail('test_nested_merges.2', commit_mails[1])
    assert_mail('test_nested_merges.3', commit_mails[2])
    assert_mail('test_nested_merges.4', commit_mails[3])
    assert_mail('test_nested_merges.5', commit_mails[4])
  end

  def test_non_ascii_filename
    create_default_mailer
    commit_new_file("日本語.txt", "日本語の文章です。", "added a file with japanese file name")
    git "push origin master"

    push_mail, commit_mails = last_mails

    assert_mail('test_non_ascii_file_name', commit_mails[0])
  end

  def test_long_word_in_commit_subject
    create_default_mailer
    sample_filename = 'sample_file'

    file_content = <<EOF 
This is a sample text file.
This file will be modified to make commits.
EOF
    commit_new_file(sample_filename, file_content, "x" * 60)

    git 'push origin master'

    push_mail, commit_mails = last_mails

    assert_mail('test_long_word_in_commit_subject', commit_mails[0])
  end
end
