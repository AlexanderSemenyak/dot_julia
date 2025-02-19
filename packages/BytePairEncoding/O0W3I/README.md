
# Table of Contents

1.  [BytePairEncoding.jl](#orgf71fdec)
2.  [API](#org57e4c00)
    1.  [Unicode Normalization](#orga334417)
3.  [Examples](#org6777a55)
4.  [Roadmap](#orgd74ca5a)


<a id="orgf71fdec"></a>

# BytePairEncoding.jl

Pure Julia implementation of  the Byte Pair Encoding(BPE) method 
in the [subword neural machine translation paper](https://arxiv.org/abs/1508.07909). It's a port of 
the original python package [subword-nmt](https://github.com/rsennrich/subword-nmt). `BytePairEncoding.jl` support different tokenize
method(with the help of WordTokenizers.jl). You can simply use `set_tokenizer([your tokenize function])` 
and then Learn the BPE map with it.


<a id="org57e4c00"></a>

# API

-   `BPELearner([vocabulary files]; num_sym, min_freq, endsym, normalizer)` 
    -   work as the learning configure.
        -   `num_sym`: how many pair to generate.
        -   `min_freq`: threshold of learned pair frequency.
        -   `endsym`: the symbol for seperate internal & last pair, if is set, it will automatically 
            invoke `set_endsym(endsym`.
        -   `normalizer`: normalizer type, default is identity(not normalized), 
            see next section for define normalization
    -   `add!(::BPELearner, newfile)`
        -   add a new file to learner.
    -   `learn!(::BPELearner)`
        -   learn the bpe map.
    -   `emit(::BPELearner, output_filename)`
        -   generate the bpe map file.
-   `Bpe(bpefile; glossaries, merge, sepsym, endsym, normalizer)`
    -   the bpe encoding related config.
        -   `merge`: how many pair to load.
        -   `sepsym`: seperator symbol for internal pair, default is "".
        -   `endsym`: end symbol of the last pair, default "</w>".
        -   `glossaries`: a list of glossaries, support both Regex & String.
        -   `normalizer`: normalizer type,  default is identity(not normalized), 
            see next section for define normalization
    -   `process_line(::Bpe, line)`: segment a given line the join as a new line, 
        leading & trailing whitesplace will remmain.
    -   `segment(::Bpe, line)`: segment a line into a list of segments
    -   `segment_token(::Bpe, token::String)`: segment a given token or a list of tokens.
-   `set_endsym(::String)`: set the end symbol, default "</w>".
-   `set_tokenizer(func)`: set the tokenizer fucntion , default is `nltk_word_tokenize`.
-   `whitespace_tokenize(str)`: simply the `split(str)` function, for use with `set_tokenizer`.


<a id="orga334417"></a>

## Unicode Normalization

support unicode normalization

-   `UtfNormalizer`
    -   wrapper type on Julia built-in unicode normalization function
        -   `UtfNormalizer(::Symbol)`: support `:NFC`, `:NFD`, `:NFKC`, `:NFKD`, `:NFKC_CF`
        -   `UtfNormalizer([option_names=all_default_false])`: options (stable, compat, 
            compose, decompose, stripignore, rejectna, newline2ls, newline2ps, newline2lf, 
            stripcc, casefold, lump, stripmark), usage example: `UtfNormalizer(stable=true, compose=true)`
    -   `normalize(::AbstractNormalizer, ::String)`: normalize given string with specific normalizer.


<a id="org6777a55"></a>

# Examples

                   _
       _       _ _(_)_     |  Documentation: https://docs.julialang.org
      (_)     | (_) (_)    |
       _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
      | | | | | | |/ _` |  |
      | | |_| | | | (_| |  |  Version 1.0.2 (2018-11-08)
     _/ |\__'_|_|_|\__'_|  |
    |__/                   |
    
    julia> using BytePairEncoding
    
    julia> using WordTokenizers
    
    julia> set_tokenizer(nltk_word_tokenize)
    tokenize (generic function with 1 method)
    
    julia> norm = UtfNormalizer(:NFKC)
    UtfNormalizer(14)
    
    julia> vocabfiles = ["./data/.....", "./another/data/....." ...]
    
    julia> bper = BPELearner(vocabfiles, 1000; normalizer=norm)
    BPELearner(num_sym=1000, min_freq=2, endsym="</w>", normailzer=UtfNormalizer)
    
    julia> learn!(bper)
    
    julia> emit(bper, "./bpe.out")
    "./bpe.out"
    
    julia> bpe = Bpe("./bpe.out"; normalizer=norm)
    Bpe(merge=-1, sepsym="", endsym="</w>", num_glossaries=0, normalizer=UtfNormalizer)
    
    julia> sample_sent =  "It's interesting that technology often works as a servant for us, yet frequently we become a
     servant to it. E-mail is a useful tool but many feel controlled by this new tool. The average business person is g
    etting about 80e-mails per day and many feel that about 80% of the messages in their \"Inbox\" are of little or no
           value. So, I have four suggestions to help you to become better at \"Erasing E-mail\".\n1.Get off the lists.
     The best way to deal with a problem is to never have it. If you are receiving a lot of unwanted e-mails, ask to be
     removed from the various lists. This would include your inclusion in unwanted lists.\n2.\"Unlisted address\". Just
     as you keep an \"unlisted\" telephone number that you share only with those whom you want to have direct access to
    , you might want to get a separate e-mail address only for the important communications you wish to receive.\n"
    "It's interesting that technology often works as a servant for us, yet frequently we become a servant to it. E-mail
     is a useful tool but many feel controlled by this new tool. The average business person is getting about 80e-mails
     per day and many feel that about 80% of the messages in their \"Inbox\" are of little or no\nvalue. So, I have fou
    r suggestions to help you to become better at \"Erasing E-mail\".\n1.Get off the lists. The best way to deal with a
     problem is to never have it. If you are receiving a lot of unwanted e-mails, ask to be removed from the various li
    sts. This would include your inclusion in unwanted lists.\n2.\"Unlisted address\". Just as you keep an \"unlisted\"
     telephone number that you share only with those whom you want to have direct access to, you might want to get a se
    parate e-mail address only for the important communications you wish to receive.\n"
    
    julia> first(split_sentences(sample_sent))
    "It's interesting that technology often works as a servant for us, yet frequently we become a servant to it."
    
    julia> segment(bpe, ans)
    42-element Array{String,1}:
     "I"        
     "t</w>"    
     "'"        
     "s</w>"    
     "inter"    
     "est"      
     "ing</w>"  
     "that</w>" 
     "t"        
     "ec"       
     "h"        
     "no"       
     "lo"       
     "g"        
     "y</w>"    
     "of"       
     "ten</w>"  
     "works</w>"
     "as</w>"   
     "a</w>"    
     ⋮          
     "us</w>"   
     ",</w>"    
     "y"        
     "et</w>"   
     "f"        
     "re"       
     "qu"       
     "ent"      
     "ly</w>"   
     "we</w>"   
     "b"        
     "ecom"     
     "e</w>"    
     "a</w>"    
     "serv"     
     "ant</w>"  
     "to</w>"   
     "it</w>"   
     ".</w>"    
    
    julia> for sentence ∈ split_sentences(sample_sent)
               println(process_line(bpe, sentence))
           end
    I t</w> ' s</w> inter est ing</w> that</w> t ec h no lo g y</w> of ten</w> works</w> as</w> a</w> serv ant</w> for<
    /w> us</w> ,</w> y et</w> f re qu ent ly</w> we</w> b ecom e</w> a</w> serv ant</w> to</w> it</w> .</w>
    E - ma il</w> is</w> a</w> us e ful</w> tool</w> but</w> many</w> fe el</w> cont ro l led</w> by</w> this</w> new</
    w> tool</w> .</w>
    T he</w> a ver age</w> b us in ess</w> pers on</w> is</w> g et ting</w> about</w> 8 0 e - ma il s</w> p er</w> day<
    /w> and</w> many</w> fe el</w> that</w> about</w> 8 0</w> %</w> of</w> the</w> m es sa ges</w> in</w> their</w> ` `
    </w> In bo x</w> ' '</w> are</w> of</w> l it t le</w> or</w> no</w>
    value</w> .</w>
    S o</w> ,</w> I</w> have</w> f our</w> su g g es tions</w> to</w> help</w> you</w> to</w> b ecom e</w> bet ter</w>
    at</w> ` `</w> E r as ing</w> E - ma il</w> ' '</w> .</w>
    1 . G et</w> of f</w> the</w> li sts</w> .</w>
    T he</w> b est</w> way</w> to</w> de al</w> with</w> a</w> pro bl em</w> is</w> to</w> n ever</w> have</w> it</w> .
    </w>
    I f</w> you</w> are</w> recei ving</w> a</w> l ot</w> of</w> un w an ted</w> e - ma il s</w> ,</w> as k</w> to</w>
    be</w> re mo ved</w> from</w> the</w> vari ous</w> li sts</w> .</w>
    T his</w> would</w> incl u de</w> your</w> incl us i on</w> in</w> un w an ted</w> li sts</w> .</w>
    2 .</w> ' '</w> U n li sted</w> ad d ress</w> ' '</w> .</w>
    J ust</w> as</w> you</w> ke ep</w> an</w> ` `</w> un li sted</w> ' '</w> t el e ph one</w> numb er</w> that</w> you
    </w> sh are</w> only</w> with</w> those</w> who m</w> you</w> want</w> to</w> have</w> di rec t</w> acc ess</w> to<
    /w> ,</w> you</w> might</w> want</w> to</w> get</w> a</w> se par ate</w> e - ma il</w> ad d ress</w> only</w> for</
    w> the</w> im por t ant</w> comm un ic ations</w> you</w> w ish</w> to</w> receive</w> .</w>
    
    julia> 


<a id="orgd74ca5a"></a>

# Roadmap

-   add more interface and function
-   add pre-learned bpe map
-   support for different bpe format
-   support custom normalization
-   support for google [sentencepiece](https://github.com/google/sentencepiece)
-   Maybe add to [Embeddings.jl](https://github.com/JuliaText/Embeddings.jl) with [bpemb](https://github.com/bheinzerling/bpemb): pre-train bpe embedding

