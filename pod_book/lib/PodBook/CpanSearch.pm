package PodBook::CpanSearch;
use Mojo::Base 'Mojolicious::Controller';
use Regexp::Common 'net';

# This action will render a template
sub form {
    my $self = shift;

    # if textfield is empty we just display the starting page
    unless ($self->param('in_text')) {
        # EXIT
        $self->render( message => 'Please make your choice.' );
        return;
    }
    
    # otherwise we continue by checnking the input

    # check the type of button pressed
    my $type;
    if ($self->param('MOBI')) {
        $type = 'mobi';
    }
    elsif ($self->param('EPUB')) {
        $type = 'epub';
    }
    else {
        # EXIT if unknown
        $self->render( message => 'ERROR: Type of ebook unknown.' );
        return;
    }

    # check if the module name in the text field is some what valid
    my $module_name;
    #TODO: No idea about the module name specs!!!
    if ($self->param('in_text') =~ m/([\d\w:-]{3,100})/) {
        $module_name = $1;
    }
    else {
        # EXIT if not matching
        $self->render( message => 'ERROR: Module name not accepted.' );
        return;
    }

    # check the remote IP... just to be sure!!! (like taint mode)
    my $remote_address;
    my $pattern = $RE{net}{IPv4};
    if ($self->tx->remote_address =~ m/^($pattern)$/) {
        $remote_address = $1;
    }
    else {
        # EXIT if not matching...
        # TODO: IPv6 will probably be a problem here...
        $self->render( message => 'ERROR: Are you a HACKER??!!.' );
        return;
    }


    # INPUT SEEMS SAVE!!!
    # So we can go on and try to process this request
    use Mojo::Asset::File;
    use Mojo::Headers;
    use PodBook::Utils::Request;
    my $book_request = PodBook::Utils::Request->new(
                                $remote_address,
                                "metacpan::$module_name",
                                $type,
                                'pod2cpan_webservice',
                       );

    # we check if the user is using the page to fast
    unless ($book_request->uid_is_allowed()) {
        # EXIT if he is to fast
        $self->render(
            message => "ERROR: To many requests from: $remote_address"
            );
        return;
    }

    # check if we have the book already in cache
    if ($book_request->is_cached()) {
        # return the book from cache

        my $book = $book_request->get_book();

        $self->send_download_to_client($book, "$module_name.$type");
    }
    else {
        print "No book in cache\n";
        # fetch from CPAN and create a Book
        # using EPublisher!
        use EPublisher;
        use EPublisher::Source::Plugin::MetaCPAN;

        use File::Temp 'tempfile';
        my ($fh, $filename) = tempfile(DIR => 'public/', SUFFIX => '.book');
        unlink $filename;

        my %config = ( 
            config => {
                pod2cpan_webservice => {
                    source => {
                        type    => 'MetaCPAN',
                        module => $module_name},
                    target => { 
                        output => $filename
                    }   
                }   
            },  
            debug  => sub {
                print "@_\n";
            },  
        );

        if ($type eq 'mobi') {
            use EPublisher::Target::Plugin::Mobi;
            $config{config}{pod2cpan_webservice}{target}{type} = 'Mobi';
        }
        elsif ($type eq 'epub') {
            use EPublisher::Target::Plugin::EPub;
            $config{config}{pod2cpan_webservice}{target}{type} = 'EPub';
        }
        else {
            # EXIT
            $self->render( message => 'ERROR: unknown book-type' );
        }

        my $publisher = EPublisher->new( %config );
        $publisher->run( [ 'pod2cpan_webservice' ] );

        use File::Slurp;
        my $bin = read_file( $filename, { binmode => ':raw' } ) ;
        unlink $filename;

        $book_request->set_book($bin);
        $book_request->cache_book(10);

        $self->send_download_to_client($bin, "$module_name.$type");
    }

    $self->render( message => 'Book cannot be delivered :-)' );
}

sub send_download_to_client {
    my ($self, $data, $name) = @_;

    my $headers = Mojo::Headers->new();
    $headers->add('Content-Type',
                  "application/x-download; name=$name");
    $headers->add('Content-Disposition',
                  "attachment; filename=$name");
    $headers->add('Content-Description','ebook');
    $self->res->content->headers($headers);

    $self->render_data($data);
}

1;
