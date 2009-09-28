#### An explanation for the complicated command used in GitCommitMailer#
#### process_create_branch and GitCommitMailer#process_update_branch
#
# Basically, that command shows all log entries that are not already covered by
# another ref - i.e. commits that are now accessible from this
# ref that were previously not accessible
#
# Consider this:
#   1 --- 2 --- O --- X --- 3 --- 4 --- N
#
# O is $old_revision for $refname
# N is $new_revision for $refname
# X is a revision pointed to by some other ref, for which we may
#   assume that an email has already been generated.
# In this case we want to issue an email containing only revisions
# 3, 4, and N.  Given (almost) by
#
#  git rev-list N ^O --not --all
#
# The reason for the "almost", is that the "--not --all" will take
# precedence over the "N", and effectively will translate to
#
#  git rev-list N ^O ^X ^N
#
# So, we need to build up the list more carefully.  git rev-parse
# will generate a list of revs that may be fed into git rev-list.
# We can get it to make the "--not --all" part and then filter out
# the "^N" with:
#
#  git rev-parse --not --all | grep -v N
#
# Then, using the --stdin switch to git rev-list we have effectively
# manufactured
#
#  git rev-list N ^O ^X
#
# This leaves a problem when someone else updates the repository
# while this script is running.  Their new value of the ref we're
# working on would be included in the "--not --all" output; and as
# our $new_revision would be an ancestor of that commit, it would exclude
# all of our commits.  What we really want is to exclude the current
# value of $refname from the --not list, rather than N itself.  So:
#
#  git rev-parse --not --all | grep -v $(git rev-parse $refname)
#
# Get's us to something pretty safe (apart from the small time
# between refname being read, and git rev-parse running - for that,
# I give up)
#
#
# Next problem, consider this:
#   * --- B --- * --- O ($old_revision)
#          \
#           * --- X --- * --- N ($new_revision)
#
# That is to say, there is no guarantee that old_revision is a strict
# subset of new_revision (it would have required a --force, but that's
# allowed).  So, we can't simply say rev-list $old_revision..$new_revision.
# Instead we find the common base of the two revs and list from
# there.
#
# As above, we need to take into account the presence of X; if
# another branch is already in the repository and points at some of
# the revisions that we are about to output - we don't want them.
# The solution is as before: git rev-parse output filtered.
#
# Finally, tags: 1 --- 2 --- O --- T --- 3 --- 4 --- N
#
# Tags pushed into the repository generate nice shortlog emails that
# summarise the commits between them and the previous tag.  However,
# those emails don't include the full commit messages that we output
# for a branch update.  Therefore we still want to output revisions
# that have been output on a tag email.
#
# Luckily, git rev-parse includes just the tool.  Instead of using
# "--all" we use "--branches"; this has the added benefit that
# "remotes/" will be ignored as well.

require "optparse"
require "ostruct"
require "time"
require "net/smtp"
require "socket"
require "nkf"
  KILO_SIZE = 1000
  DEFAULT_MAX_SIZE = "100M"


       @reference.sub(/\A.*\/.*\//,'');
    attr_reader :old_revision, :new_revision, :reference, :reference_type, :log
    attr_reader :author, :author_email, :date, :subject, :change_type
    def initialize(old_revision, new_revision, reference,
                   reference_type, change_type, log)
      @reference_type = reference_type
      @author_email = get_record("%an <%ae>")
        "X-Git-Reftype: #{reference_type}" ]
    CHANGE_TYPE = {
      :create => "created",
      :update => "updated",
      :delete => "deleted",
    }
      attr_reader :old_revision, :new_revision, :from_file, :to_file
      attr_reader :added_line, :deleted_line, :body, :type
      attr_reader :deleted_file_mode, :new_file_mode, :old_mode, :new_mode
      attr_reader :similarity_index
          @from_file = $1
          @to_file = $2
      def mode_changed?
        @is_mode_changed
      end

        @is_mode_changed = false

          when /\A--- (a\/.*|\/dev\/null)\z/
          when /\A\+\+\+ (b\/.*|\/dev\/null)\z/
          when /\Anew file mode (.*)\z/
            @type = :added
            @new_file_mode = $1
          when /\Adeleted file mode (.*)\z/
            @deleted_file_mode = $1
          when /\ABinary files (.*) and (.*) differ\z/
          when /\Aindex ([0-9a-f]{7})\.\.([0-9a-f]{7})/
            @old_blob = $1
            @new_blob = $2
          when /\Arename (from|to) (.*)\z/
            @type = :renamed
          when /\Acopy (from|to) (.*)\z/
            @type = :copied
          when /\Asimilarity index (.*)\z/
            @similarity_index = $1
          when /\Aold mode (.*)\z/
            @old_mode = $1
            @is_mode_changed = true
          when /\Anew mode (.*)\z/
            @new_mode = $1
            @is_mode_changed = true
            puts "needs to parse: " + line
           "--- #{@from_file}    #{format_time(@old_date)} (#{@old_revision[0,7]})\n" +
           "+++ #{@to_file}    #{format_time(@new_date)} (#{@new_revision[0,7]})\n"
           "(Binary files differ)\n"
        @to_file # the new file entity when copied and renamed
      def link
        file
      def file_path
        file
    attr_reader :revision, :author, :date, :subject, :log, :commit_id
    attr_reader :author_email, :diffs, :added_files, :copied_files
    attr_reader :deleted_files, :updated_files, :renamed_files
      initialize_by_getting_records
      parse_file_status

      sub_paths('driver')
    def sub_paths(prefix)
      prefixes = prefix.split(/\/+/)
      results = []
      @diffs.each do |diff|
        paths = diff.file_path.split(/\/+/)
        if prefixes.size < paths.size and prefixes == paths[0, prefixes.size]
          results << paths[prefixes.size]
        end
      end
      results
    end

    def initialize_by_getting_records
      @author_email = get_record("%an <%ae>")
      @subject = get_record("%s")
    def parse_diff
      f = IO.popen("git log -n 1 --pretty=format:'' -C -p #{@revision}")
      f.gets #removes the first empty line

      #f = IO.popen("git diff #{revision}~ #{revision}")

      @diffs = []
      lines = []

      line = f.gets
      lines << line.rstrip if line #take out the very first 'diff --git' header
      while line = f.gets
        line.rstrip!
        if line =~ /\Adiff --git/
          @diffs << DiffPerFile.new(lines, @revision)
          lines = [line]
        else
          lines << line
        end
      end
      
      #create the last diff terminated by the EOF
      @diffs << DiffPerFile.new(lines, @revision) if lines.length > 0
    end

    def parse_file_status
      `git log -n 1 --pretty=format:'' -C --name-status #{@revision}`.
      lines.each do |line|
        line.rstrip!
        if line =~ /\A([^\t]*?)\t([^\t]*?)\z/
        elsif line =~ /\A([^\t]*?)\t([^\t]*?)\t([^\t]*?)\z/
          status = $1
          from_file = $2
          to_file = $3

          case status
          when /^R/ # Renamed
            @renamed_files << [from_file, to_file]
          when /^C/ # Copied
            @copied_files << [from_file, to_file]
          end
      `git log -n 1 --pretty=format:'#{record}' #{revision}`.strip
        puts "######Got: old_rev:#{old_revision} new_rev:#{new_revision} #{reference}"
        catch (:no_email) do
          mailer.process_single_ref_change(old_revision, new_revision, reference)
        end
      ENV['GIT_DIR'] = options.repository
      puts "@@@@@@@setting GIT_DIR to #{options.repository}"
  def detect_change_type
    if old_revision =~ /0{40}/ and new_revision =~ /0{40}/
      raise "Invalid revision hash"
    elsif old_revision !~ /0{40}/ and new_revision !~ /0{40}/
      :update
      :create
      :delete
      raise "Invalid revision hash"
  end
  def detect_revision_type(change_type)
    when :create, :update
      `git cat-file -t #@new_revision`.strip
    when :delete
      `git cat-file -t #@old_revision`.strip
  end
  def detect_reference_type(revision_type)
    if reference =~ /refs\/tags\/.*/ and revision_type == "commit"
      "tag"
    elsif reference =~ /refs\/tags\/.*/ and revision_type == "tag"
      "annotated tag"
    elsif reference =~ /refs\/heads\/.*/ and revision_type == "commit"
      "branch"
    elsif reference =~ /refs\/remotes\/.*/ and revision_type == "commit"
      throw :no_email
      raise "Unknown type of update to #@reference (#{revision_type})"
  end
  def return_push_message_and_yield(reference_type, change_type, block)
    if reference_type == "branch" and change_type == :update
      process_update_branch(block)
    elsif reference_type == "branch" and change_type == :create
      process_create_branch(block)
    elsif reference_type == "branch" and change_type == :delete
      process_delete_branch(block)
    elsif reference_type == "annotated tag" and change_type == :update
      process_update_atag
    elsif reference_type == "annotated tag" and change_type == :create
      process_create_atag
    elsif reference_type == "annotated tag" and change_type == :delete
      process_delete_atag
  end

  def each_revision(&block)
    change_type = detect_change_type
    revision_type = detect_revision_type(change_type)
    reference_type = detect_reference_type(revision_type)

    push_messsage = return_push_message_and_yield(reference_type, change_type,
                                                  block)
    [reference_type, change_type, push_messsage]
  end

  def excluded_revisions
     # refer to the long comment located at the top of this file for the
     # explanation of this command.
     current_reference_rev = `git rev-parse #@reference`.strip
     `git rev-parse --not --branches`.lines.find_all { |line|
       line.strip!
       not line.index(current_reference_rev)
     }.join(' ')
    msg = "Branch (#@reference) is created.\n"
    `git rev-list #@new_revision #{excluded_revisions}`.lines.
    reverse_each { |revision|
      revision.strip!
      block.call(revision)
      subject = GitCommitMailer.get_record(revision,'%s')
      commit_list << "     via  #{revision[0,7]} #{subject}\n"
    if commit_list.length > 0
      commit_list[-1].sub!(/\A     via  /,'     at   ')
      msg << commit_list.join
    end
  def explain_rewind
<<EOF
This update discarded existing revisions and left the branch pointing at
a previous point in the repository history.

 * -- * -- N (#{new_revision[0,7]})
            \\
             O <- O <- O (#{old_revision[0,7]})

The removed revisions are not necessarilly gone - if another reference
still refers to them they will stay in the repository.
EOF
  end

  def explain_rewind_and_new_commits
<<EOF
This update added new revisions after undoing existing revisions.  That is
to say, the old revision is not a strict subset of the new revision.  This
situation occurs when you --force push a change and generate a repository
containing something like this:

 * -- * -- B <- O <- O <- O (#{old_revision[0,7]})
            \\
             N -> N -> N (#{new_revision[0,7]})

When this happens we assume that you've already had alert emails for all
of the O revisions, and so we here report only the revisions in the N
branch from the common base, B.
EOF
  end

    msg = "Branch (#@reference) is updated.\n"
    `git rev-list #@new_revision..#@old_revision`.lines.each { |revision|
      subject = GitCommitMailer.get_record(revision, '%s')
      revision_list << "discards  #{revision[0,7]} #{subject}\n"
      fast_forward = true 
      subject = GitCommitMailer.get_record(old_revision,'%s')
      revision_list << "    from  #{old_revision[0,7]} #{subject}\n"
    tmp = []
    `git rev-list #@old_revision..#@new_revision`.lines.each { |revision|
      subject = GitCommitMailer.get_record(revision, '%s')
      tmp << "     via  #{revision[0,7]} #{subject}\n"
    revision_list.concat(tmp.reverse)
      baserev = `git merge-base #@old_revision #@new_revision`.strip
        msg << explain_rewind
        msg << explain_rewind_and_new_commits
    msg << revision_list.join
    no_actual_output = true
      `git rev-list #@old_revision..#@new_revision #{excluded_revisions}`.lines.
      reverse_each { |revision|
        block.call(revision.strip)
        no_actual_output = false
      }
    end
    if rewind_only or no_actual_output
    "Branch (#@reference) is deleted.\n" +
    "       was  #@old_revision\n\n" +
    `git show -s --pretty=oneline #@old_revision`
  def process_create_atag
    "Annotated tag (#@reference) is created.\n" +
    "        at  #@new_revision (tag)\n" +
    process_atag
  end
  def process_update_atag
    "Annotated tag (#@reference) is updated.\n" +
    "        to  #@new_revision (tag)\n" +
    "      from  #@old_revision (which is now obsolete)\n" +
    process_atag
  def process_delete_atag
    "Annotated tag (#@reference) is deleted.\n" +
    "       was  #@old_revision\n\n" +
    `git show -s --pretty=oneline #@old_revision`
  def process_atag
    msg = ''
    # Use git for-each-ref to pull out the individual fields from the
    # tag
    tag_object = `git for-each-ref --format='%(*objectname)' #@reference`.strip
    tag_type = `git for-each-ref --format='%(*objecttype)' #@reference`.strip
    tagger = `git for-each-ref --format='%(taggername)' #@reference`.strip
    tagged = `git for-each-ref --format='%(taggerdate)' #@reference`.strip
    prev_tag = nil

    msg << "   tagging  #{tag_object} (#{tag_type})\n"
    case tag_type
    when "commit"
      # If the tagged object is a commit, then we assume this is a
      # release, and so we calculate which tag this tag is
      # replacing
      prev_tag = `git describe --abbrev=0 #@new_revision^`.strip

      msg << "  replaces  #{prev_tag}\n" if prev_tag
    else
      msg << "    length  #{`git cat-file -s #{tag_object}`.strip} bytes\n"
    end
    msg << " tagged by  #{tagger}\n"
    msg << "        on  #{tagged}\n\n"

    # Show the content of the tag message; this might contain a change
    # log or release notes so is worth displaying.
    tag_content = `git cat-file tag #@new_revision`.split("\n")
    tag_content.shift while not tag_content[0].empty?
    tag_content.shift
    msg << tag_content.join("\n")

    case tag_type
    when "commit"
      # Only commit tags make sense to have rev-list operations
      # performed on them
      if prev_tag
        # Show changes since the previous release
        msg << `git rev-list --pretty=short \"#{prev_tag}..#@new_revision\" |
                git shortlog`
      else
        # No previous tag, show all the changes since time
        # began
        msg << `git rev-list --pretty=short #@new_revision | git shortlog`
      end
    else
      # XXX: Is there anything useful we can do for non-commit
      # objects?
    end
    msg
    @push_info = nil


    if push_info_args
      @push_info = PushInfo.new(old_revision, new_revision, reference,
                                *push_info_args)
    else
      return
    end
    #@info = @push_info
    #send_mail make_mail
    sleep 0.1
      body << renamed_files
    else
      raise "a new Info Class?"
      rv << files.collect do |from_file, to_file|
    #{to_file}
      (from #{from_file})
  def renamed_files
    changed_files("Renamed", @info.renamed_files) do |rv, files|
      rv << files.collect do |from_file, to_file|
        <<-INFO
    #{to_file}
      (from #{from_file})
INFO
    :renamed => "Renamed",
    diff_info.each do |desc|
      similarity_index = ""
      file_mode = ""
      case diff.type
      when :added
        command = "show"
        file_mode = " Mode: #{diff.new_file_mode}"
      when :deleted
        command = "show"
        file_mode = " Mode: #{diff.deleted_file_mode}"
        rev = diff.old_revision
      when :modified
        command = "diff"
        args.concat(["-r", diff.old_revision[0,7], diff.new_revision[0,7],
                     diff.link])
      when :renamed
        command = "diff"
        args.concat(["-C","--diff-filter=R",
                     "-r", diff.old_revision[0,7], diff.new_revision[0,7], "--",
                     diff.from_file, diff.to_file])
        similarity_index = "Similarity: #{diff.similarity_index}"
      when :copied
        command = "diff"
        args.concat(["-C","--diff-filter=C",
                     "-r", diff.old_revision[0,7], diff.new_revision[0,7], "--",
                     diff.from_file, diff.to_file])
        similarity_index = "Similarity: #{diff.similarity_index}"
      else
        raise "unknown diff type: #{diff.type}"
      end
      if command == "show"
        args.concat(["#{rev[0,7]}:#{diff.link}"])
      end

      command += " #{args.join(' ')}" unless args.empty?
      desc =  "  #{CHANGED_TYPE[diff.type]}: #{diff.file} (#{line_info})"
      desc << "#{file_mode}#{similarity_index}\n"
      if diff.mode_changed?
        desc << "  Mode: #{diff.old_mode} -> #{diff.new_mode}\n"
      end
      desc << "#{"=" * 67}\n"
    % git #{command}
      desc
    headers << "Subject: #{(@name+' ') if @name}#{make_subject}"
  def detect_project
    project = File.open("#{repository}/description").gets.strip
    # Check if the description is unchanged from it's default, and shorten it to
    # a more manageable length if it is
    if project =~ /Unnamed repository.*$/
      project = nil
    end

    project
  end

  def make_subject
    subject = ""
    project = detect_project
    revision_info = "#{@info.revision[0,7]}"

    if @info.class == CommitInfo
      if show_path?
        _affected_paths = affected_paths
        unless _affected_paths.empty?
          revision_info = "(#{_affected_paths.join(',')}) #{revision_info}"

      if project
        subject << "[commit #{project} #{@info.short_reference} " +
                   "#{revision_info}] "
      else
        subject << "#{revision_info}: "
      end
      subject << @info.subject
    elsif @info.class == PushInfo
      if project
        subject << "[push #{project}] "
      else
        subject << "[push] "
      end
      subject << "#{@info.reference_type} (#{@info.short_reference}) is" +
                 " #{PushInfo::CHANGE_TYPE[@info.change_type]}."
    else
      raise "a new Info class?"

    #NKF.nkf("-WM", subject)
  end

  def affected_paths
    paths = []
    sub_paths = @info.sub_paths('')
    paths.concat(sub_paths)
      _to, *_ = ARGV.reject {|arg| /^-/.match(arg)}
  #if to.empty?
  #else
  #end